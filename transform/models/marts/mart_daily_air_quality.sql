/*
mart_daily_air_quality — daily aggregated air quality metrics per station and pollutant.

Partition strategy:
  - partition key: measurement_date
      Every dashboard query filters on a date range; partitioning on
      measurement_date means Athena reads only the relevant date partitions,
      minimising scan cost and query latency.

Note: measurement_date must be the last column in the SELECT because Athena/Hive
requires partition columns to appear at the end of the table definition.

AQI calculation:
  - Computed only for parameter = 'pm25' using US EPA 2024 updated breakpoints
    (annual NAAQS lowered from 12.0 to 9.0 µg/m³ in May 2024).
  - Piecewise linear interpolation: AQI = ((I_HI-I_LO)/(BP_HI-BP_LO))*(C-BP_LO)+I_LO
  - NULL for all non-PM2.5 parameters.

Exceedance flags (PM2.5 only):
  - exceeds_who_24h: avg_value > 15  µg/m³ (WHO AQG 2021 24-hour guideline)
  - exceeds_qcvn:    avg_value > 50  µg/m³ (QCVN 05:2023 24-hour standard)

Grain: one row per measurement_date × location_id × parameter.
Source: int_measurements_enriched (staging measurements + station metadata).
*/

{{ config(
    materialized   = 'table',
    partitioned_by = ['measurement_date']
) }}

with source as (

    select * from {{ ref('int_measurements_enriched') }}

),

aggregated as (

    select
        city,
        province,
        parameter,
        location_id,
        location_name,
        station_lat,
        station_lon,
        sensor_type,

        round(avg(measurement_value), 4)  as avg_value,
        round(max(measurement_value), 4)  as max_value,
        round(min(measurement_value), 4)  as min_value,
        count(*)                          as reading_count,
        count(distinct sensor_id)         as sensor_count,

        measurement_date

    from source

    group by
        measurement_date,
        city,
        province,
        parameter,
        location_id,
        location_name,
        station_lat,
        station_lon,
        sensor_type

)

select
    city,
    province,
    parameter,
    location_id,
    location_name,
    station_lat,
    station_lon,
    sensor_type,
    avg_value,
    max_value,
    min_value,
    reading_count,
    sensor_count,

    -- US EPA 2024 PM2.5 AQI (piecewise linear, NULL for non-PM2.5 rows)
    case
        when parameter != 'pm25' then null
        when avg_value <=   9.0  then cast(round(( 50 -  0) / (  9.0 -  0.0) * (avg_value -   0.0) +   0) as int)
        when avg_value <=  35.4  then cast(round((100 - 51) / ( 35.4 -  9.1) * (avg_value -   9.1) +  51) as int)
        when avg_value <=  55.4  then cast(round((150 -101) / ( 55.4 - 35.5) * (avg_value -  35.5) + 101) as int)
        when avg_value <= 125.4  then cast(round((200 -151) / (125.4 - 55.5) * (avg_value -  55.5) + 151) as int)
        when avg_value <= 225.4  then cast(round((300 -201) / (225.4 -125.5) * (avg_value - 125.5) + 201) as int)
        when avg_value <= 325.4  then cast(round((500 -301) / (325.4 -225.5) * (avg_value - 225.5) + 301) as int)
        else 500
    end as aqi_value,

    -- AQI category label (EPA 2024)
    case
        when parameter != 'pm25'  then null
        when avg_value <=   9.0   then 'Good'
        when avg_value <=  35.4   then 'Moderate'
        when avg_value <=  55.4   then 'Unhealthy for Sensitive Groups'
        when avg_value <= 125.4   then 'Unhealthy'
        when avg_value <= 225.4   then 'Very Unhealthy'
        else                           'Hazardous'
    end as aqi_category,

    -- Exceedance flags (NULL for non-PM2.5 parameters)
    case when parameter = 'pm25' then (avg_value > 15) end as exceeds_who_24h,
    case when parameter = 'pm25' then (avg_value > 50) end as exceeds_qcvn,

    -- partition column must be last
    measurement_date

from aggregated
order by measurement_date desc, city, parameter

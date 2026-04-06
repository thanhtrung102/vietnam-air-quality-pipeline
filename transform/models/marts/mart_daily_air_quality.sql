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

Exceedance flags and health metrics (PM2.5 only):
  - exceeds_who_24h:      avg_value > 15  µg/m³ (WHO AQG 2021 24-hour guideline)
  - exceeds_qcvn:         avg_value > 50  µg/m³ (QCVN 05:2023 24-hour standard)
  - who_compliant_day:    1 if avg_value ≤ 15 µg/m³, else 0 (use for WHO compliance % in health_summary)
  - cigarette_equivalent: avg_value / 22.0  (1 cigarette ≈ 22 µg/m³ PM2.5/day, Berkeley Earth standard)

Data quality flags:
  - is_outlier_station: 1 for known stations with confirmed calibration/initialisation
      artefacts that produce unrepresentative readings. Currently:
        6273386 (VNUHCMUS Campus 1, HCMC) — started Mar 2026, readings ≫ all other HCMC
        stations and IQAir reference data; likely sensor initialisation artefact.
      Downstream marts (health_summary, exceedance_stats) exclude these rows.
      Add new station IDs here as data quality issues are identified.

  - corrected_pm25: bias-corrected PM2.5 for low-cost optical particle counters
      (sensor_type = 'low-cost sensor'). AirGradient field studies show raw PMS5003
      readings overestimate true PM2.5 by ~50% in high-humidity tropical conditions
      (RH > 70%). Correction: corrected = avg_value / 1.50.
      Reference stations (BAM/TEOM) are unaffected (corrected_pm25 = avg_value).
      NULL for non-PM2.5 parameters.

Grain: one row per measurement_date × location_id × parameter.
Source: int_measurements_enriched (staging measurements + station metadata).
*/

{{ config(
    materialized      = 'table',
    partitioned_by    = ['measurement_date'],
    format            = 'parquet',
    write_compression = 'snappy'
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

    -- US EPA 2024 AQI (piecewise linear interpolation).
    -- PM2.5: 24-hour breakpoints (µg/m³), updated May 2024 (annual NAAQS 12→9 µg/m³).
    -- PM10:  24-hour breakpoints (µg/m³).
    -- O3/NO2/SO2/CO require unit conversion (µg/m³ → ppm/ppb) and sub-daily
    -- averaging windows — excluded pending normalisation of units in staging.
    case
        when parameter = 'pm25' then
            case
                when avg_value <=   9.0  then cast(round(( 50 -  0) / (  9.0 -  0.0) * (avg_value -   0.0) +   0) as int)
                when avg_value <=  35.4  then cast(round((100 - 51) / ( 35.4 -  9.1) * (avg_value -   9.1) +  51) as int)
                when avg_value <=  55.4  then cast(round((150 -101) / ( 55.4 - 35.5) * (avg_value -  35.5) + 101) as int)
                when avg_value <= 125.4  then cast(round((200 -151) / (125.4 - 55.5) * (avg_value -  55.5) + 151) as int)
                when avg_value <= 225.4  then cast(round((300 -201) / (225.4 -125.5) * (avg_value - 125.5) + 201) as int)
                when avg_value <= 325.4  then cast(round((500 -301) / (325.4 -225.5) * (avg_value - 225.5) + 301) as int)
                else 500
            end
        when parameter = 'pm10' then
            case
                when avg_value <=  54.0  then cast(round(( 50 -  0) / ( 54.0 -  0.0) * (avg_value -   0.0) +   0) as int)
                when avg_value <= 154.0  then cast(round((100 - 51) / (154.0 - 55.0) * (avg_value -  55.0) +  51) as int)
                when avg_value <= 254.0  then cast(round((150 -101) / (254.0 -155.0) * (avg_value - 155.0) + 101) as int)
                when avg_value <= 354.0  then cast(round((200 -151) / (354.0 -255.0) * (avg_value - 255.0) + 151) as int)
                when avg_value <= 424.0  then cast(round((300 -201) / (424.0 -355.0) * (avg_value - 355.0) + 201) as int)
                when avg_value <= 604.0  then cast(round((500 -301) / (604.0 -425.0) * (avg_value - 425.0) + 301) as int)
                else 500
            end
        else null
    end as aqi_value,

    -- AQI health category label derived from aqi_value breakpoints
    case
        when parameter not in ('pm25', 'pm10') then null
        when avg_value is null                 then null
        -- re-derive from the same breakpoints to avoid a self-reference
        when parameter = 'pm25' then
            case
                when avg_value <=   9.0  then 'Good'
                when avg_value <=  35.4  then 'Moderate'
                when avg_value <=  55.4  then 'Unhealthy for Sensitive Groups'
                when avg_value <= 125.4  then 'Unhealthy'
                when avg_value <= 225.4  then 'Very Unhealthy'
                else                          'Hazardous'
            end
        when parameter = 'pm10' then
            case
                when avg_value <=  54.0  then 'Good'
                when avg_value <= 154.0  then 'Moderate'
                when avg_value <= 254.0  then 'Unhealthy for Sensitive Groups'
                when avg_value <= 354.0  then 'Unhealthy'
                when avg_value <= 424.0  then 'Very Unhealthy'
                else                          'Hazardous'
            end
    end as aqi_category,

    -- Exceedance flags (NULL for non-PM2.5 parameters)
    case when parameter = 'pm25' then (avg_value > 15) end as exceeds_who_24h,
    case when parameter = 'pm25' then (avg_value > 50) end as exceeds_qcvn,

    -- WHO compliance flag: 1 if this day's PM2.5 avg meets the WHO 24-hour guideline (≤15 µg/m³)
    -- NULL for non-PM2.5 parameters; use in health_summary aggregation
    case when parameter = 'pm25' then cast(avg_value <= 15 as int) end as who_compliant_day,

    -- Cigarette equivalent: how many cigarettes/day of PM2.5 exposure this reading represents.
    -- Methodology: 1 cigarette ≈ 22 µg/m³ PM2.5 over 24 hours (Berkeley Earth / aqi.in standard).
    -- NULL for non-PM2.5 parameters.
    case when parameter = 'pm25' then round(avg_value / 22.0, 2) end as cigarette_equivalent,

    -- Outlier station flag: 1 for stations with known calibration/initialisation artefacts.
    -- Use WHERE is_outlier_station = 0 in downstream analytics to exclude bad readings.
    -- See header comment for current list of flagged station IDs.
    case
        when location_id in (
            '6273386'   -- VNUHCMUS Campus 1, HCMC: artefact readings from Mar 2026 startup
        ) then 1
        else 0
    end as is_outlier_station,

    -- Bias-corrected PM2.5 for low-cost optical sensors (PMS5003 family).
    -- Raw readings overestimate by ~50% in tropical high-humidity conditions (AirGradient, 2023).
    -- corrected_pm25 = avg_value / 1.50 for low-cost sensors; = avg_value for reference instruments.
    -- NULL for non-PM2.5 parameters.
    case
        when parameter = 'pm25' then
            case
                when lower(sensor_type) like '%low%cost%'
                  or lower(sensor_type) like '%low_cost%'
                  or lower(sensor_type) = 'low-cost sensor'
                    then round(avg_value / 1.50, 4)
                else avg_value
            end
        else null
    end as corrected_pm25,

    -- partition column must be last
    measurement_date

from aggregated

/*
mart_diurnal_profile — average pollutant concentration by hour of day (Vietnam local time).

Grain: location_id × parameter × hour_of_day × day_type × season

Answers: "At what hour is PM2.5 worst in Hanoi on a weekday in winter?"

Methodology:
  - measured_at is stored as UTC. Vietnam is UTC+7 (no daylight saving).
    Adding 7 hours converts to local time before extracting the hour.
  - day_type splits weekdays (Mon–Fri) from weekends (Sat–Sun) because traffic-driven
    diurnal peaks (07–09 morning rush, 17–19 evening rush) are significantly attenuated
    on weekends. Reference: namanhnt/Hanoi-Air-Quality-Analysis EDA findings.
  - season splits the NE monsoon (Nov–Mar) from the SW monsoon (Jun–Sep) because
    boundary-layer dynamics and wet scavenging fundamentally change the diurnal shape:
    monsoon season suppresses nighttime accumulation and shifts afternoon lows earlier.
  - reading_count is the total number of individual measurements contributing to
    each bucket (not the number of days).

Use in dashboard:
  - Line chart: X = hour_of_day (0–23), Y = avg_value, series = city, filter = day_type
    → isolates traffic signal from background; weekday peaks at 07–09 / 17–19 Hanoi
  - Faceted chart: day_type × season shows all four regimes in one view
  - Heatmap: X = hour_of_day, Y = month_of_year (join with mart_monthly_profile
    on location_id + parameter), colour = avg_value
*/

{{ config(materialized = 'table', partitioned_by = [], format = 'parquet', write_compression = 'snappy') }}

with labelled as (

    select
        location_id,
        location_name,
        city,
        province,
        sensor_type,
        is_outlier_station,
        parameter,
        measurement_value,
        -- Convert UTC → Vietnam local time (UTC+7, no DST)
        hour(measured_at + interval '7' hour) as hour_of_day,

        -- Weekday vs weekend (group before aggregating to avoid Saturday + Sunday = 2 rows)
        case
            when day_of_week(date(measured_at + interval '7' hour)) in (6, 7)
                then 'Weekend'
            else 'Weekday'
        end as day_type,

        -- Vietnam meteorological season
        case
            when month(date(measured_at + interval '7' hour)) in (11, 12, 1, 2, 3)
                then 'NE Monsoon (Nov-Mar)'
            when month(date(measured_at + interval '7' hour)) in (4, 5)
                then 'Transition (Apr-May)'
            when month(date(measured_at + interval '7' hour)) in (6, 7, 8, 9)
                then 'SW Monsoon (Jun-Sep)'
            else 'Transition (Oct)'
        end as season

    from {{ ref('int_measurements_enriched') }}

)

select
    location_id,
    location_name,
    city,
    province,
    sensor_type,
    is_outlier_station,
    parameter,
    hour_of_day,
    day_type,
    season,
    round(avg(measurement_value), 4) as avg_value,
    round(max(measurement_value), 4) as max_value,
    round(min(measurement_value), 4) as min_value,
    count(*)                         as reading_count

from labelled

group by
    location_id,
    location_name,
    city,
    province,
    sensor_type,
    is_outlier_station,
    parameter,
    hour_of_day,
    day_type,
    season


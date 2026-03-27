/*
mart_diurnal_profile — average pollutant concentration by hour of day (Vietnam local time).

Grain: location_id × parameter × hour_of_day (0–23, UTC+7)

Answers: "At what hour is PM2.5 worst in Hanoi?"

Methodology:
  - measured_at is stored as UTC. Vietnam is UTC+7 (no daylight saving).
    Adding 7 hours converts to local time before extracting the hour.
  - Averages are computed across all available dates (the full 2023–2026 range).
  - reading_count is the total number of individual measurements contributing to
    each hour bucket (not the number of days).

Use in dashboard:
  - Heatmap: X = hour_of_day, Y = month_of_year (join with mart_monthly_profile
    on location_id + parameter), colour = avg_value
  - Line chart: X = hour_of_day (0–23), Y = avg_value, series = city
    → shows rush-hour peaks (07–09, 17–19) vs. overnight lows
*/

{{ config(materialized = 'table', partitioned_by = [], format = 'parquet', write_compression = 'snappy') }}

select
    location_id,
    location_name,
    city,
    province,
    sensor_type,
    parameter,
    -- Convert UTC → Vietnam local time (UTC+7, no DST)
    hour(measured_at + interval '7' hour)   as hour_of_day,
    round(avg(measurement_value), 4)        as avg_value,
    round(max(measurement_value), 4)        as max_value,
    round(min(measurement_value), 4)        as min_value,
    count(*)                                as reading_count

from {{ ref('int_measurements_enriched') }}

group by
    location_id,
    location_name,
    city,
    province,
    sensor_type,
    parameter,
    hour(measured_at + interval '7' hour)


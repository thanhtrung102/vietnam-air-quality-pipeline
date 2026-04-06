/*
mart_exceedance_stats — monthly WHO and QCVN PM2.5 exceedance rates per city.

Grain: city × parameter × year × month_of_year

Answers:
  "Is the WHO exceedance rate in Hanoi getting worse each January?"
  "How many days per month does Hanoi exceed the Vietnam QCVN standard?"

Thresholds used:
  WHO AQG 2021 (24-hour)  : PM2.5 > 15 µg/m³
  QCVN 05:2023 (24-hour)  : PM2.5 > 50 µg/m³

Source exclusion:
  Station 6273386 (VNUHCMUS Campus 1) is excluded via is_outlier_station = 1.
  This station reported artefact readings up to ~2,000 µg/m³ from March 2026 startup
  and would inflate HCMC exceedance rates to ~100% for that period.

Use in dashboard:
  - Line chart: X = month_of_year, Y = who_exceedance_rate, series = year
    → shows whether the same calendar month is getting worse year over year
  - Clustered bar: X = year, Y = who_exceedance_days × month, filter = city
    → monthly heatmap of exceedance burden

Note: grain is city × parameter; each city row is the average across all non-outlier
stations in that city on that date (same methodology as mart_health_summary city_daily CTE).
*/

{{ config(materialized = 'table', partitioned_by = [], format = 'parquet', write_compression = 'snappy') }}

with city_daily as (

    -- Collapse multi-station cities to one city-level daily PM2.5 average
    -- (mirrors the aggregation in mart_health_summary to ensure consistency)
    select
        city,
        parameter,
        measurement_date,
        year(measurement_date)      as year,
        month(measurement_date)     as month_of_year,
        avg(avg_value)              as pm25_city_avg

    from {{ ref('mart_daily_air_quality') }}
    where parameter = 'pm25'
      and is_outlier_station = 0

    group by
        city,
        parameter,
        measurement_date

)

select
    city,
    parameter,
    year,
    month_of_year,

    count(*)                                                         as total_days,
    count_if(pm25_city_avg > 15)                                     as who_exceedance_days,
    count_if(pm25_city_avg > 50)                                     as qcvn_exceedance_days,
    round(100.0 * count_if(pm25_city_avg > 15) / count(*), 1)       as who_exceedance_rate,
    round(100.0 * count_if(pm25_city_avg > 50) / count(*), 1)       as qcvn_exceedance_rate,
    round(avg(pm25_city_avg), 2)                                     as avg_pm25,
    round(approx_percentile(pm25_city_avg, 0.95), 2)                 as p95_pm25

from city_daily

group by
    city,
    parameter,
    year,
    month_of_year
/*
mart_annual_monthly_trend — city-level PM2.5 by year × month of year.

Grain: city × year × month_of_year

Source: mart_daily_air_quality (pm25, is_outlier_station = 0)

Methodology:
  Step 1 (city_daily CTE): collapse all non-outlier PM2.5 stations in a city to
  a single city-level daily average — identical to mart_health_summary. Avoids
  double-counting multi-station cities (Hanoi has up to 16 active stations).
  Step 2: aggregate city-level daily averages into year × month buckets.

This is the only mart that enables apples-to-apples calendar-month comparisons
across years ("Is Jan 2025 worse than Jan 2024 in Hanoi?"). mart_monthly_profile
averages across all years, losing the year dimension.

Key metrics:
  avg_pm25          — mean city-level PM2.5 for the month
  max_pm25          — peak daily city avg in the month
  p95_pm25          — 95th-percentile daily city avg (robustly captures pollution spikes)
  who_exceedance_rate — % of days in the month where city avg > 15 µg/m³
  total_days        — days with PM2.5 data in this city/year/month

Use in dashboard:
  - Side-by-side grouped bar: X = month, Y = avg_pm25, bar groups = year (2023/24/25)
    → shows whether the same calendar month is getting worse year over year
  - YoY delta line: avg_pm25[year N] - avg_pm25[year N-1] per month per city
    → positive delta = deterioration; negative = improvement
  - Predictive baseline: confirms the upward trend SARIMA/Prophet must extrapolate

Validation expectation:
  Hanoi January: 2023 ~68 µg/m³ → 2024 ~71 µg/m³ → 2025 ~74 µg/m³ (upward)
  HCMC January:  2023 ~22 µg/m³ → 2024 ~27 µg/m³ → 2025 ~36 µg/m³ (faster increase)
*/

{{ config(materialized = 'table', partitioned_by = [], format = 'parquet', write_compression = 'snappy') }}

with city_daily as (

    -- Collapse multi-station cities to one city-level daily PM2.5 average
    select
        city,
        province,
        measurement_date,
        year(measurement_date)      as year,
        month(measurement_date)     as month_of_year,
        avg(avg_value)              as pm25_city_avg

    from {{ ref('mart_daily_air_quality') }}
    where parameter = 'pm25'
      and is_outlier_station = 0

    group by
        city,
        province,
        measurement_date

)

select
    city,
    province,
    year,
    month_of_year,

    count(*)                                                          as total_days,
    round(avg(pm25_city_avg), 2)                                      as avg_pm25,
    round(max(pm25_city_avg), 2)                                      as max_pm25,
    round(approx_percentile(pm25_city_avg, 0.95), 2)                  as p95_pm25,
    round(100.0 * count_if(pm25_city_avg > 15) / count(*), 1)        as who_exceedance_rate,
    round(100.0 * count_if(pm25_city_avg > 50) / count(*), 1)        as qcvn_exceedance_rate

from city_daily

group by
    city,
    province,
    year,
    month_of_year

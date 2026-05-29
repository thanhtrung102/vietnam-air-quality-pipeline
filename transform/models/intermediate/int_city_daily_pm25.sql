/*
int_city_daily_pm25 — one city-level daily PM2.5 average per city × date.

Collapses all non-outlier PM2.5 stations in a city into a single representative
daily average, so multi-station cities (Hanoi: up to 16 active stations) are not
double-counted when aggregated upward into annual / monthly / health marts.

This "collapse to one city-daily pm25 avg" step was previously duplicated verbatim
in three marts (mart_health_summary, mart_exceedance_stats, mart_annual_monthly_trend).
Extracting it here guarantees the three marts share an identical city-daily basis.

Filters (same as the prior inline CTEs):
  - parameter = 'pm25'
  - is_outlier_station = 0   (excludes station 6273386, VNUHCMUS Campus 1 artefacts)

Grain: one row per city × measurement_date.
Downstream marts derive year / month / AQI category / cigarette-equivalent /
WHO-compliance from pm25_city_avg, so this model deliberately stays minimal.

pm25_city_avg is deliberately UNROUNDED here: the prior inline CTEs differed in
rounding (mart_health_summary rounded to 4 dp before its annual aggregation;
mart_exceedance_stats and mart_annual_monthly_trend used the raw average). Each
mart re-applies its own rounding so outputs are byte-for-byte preserved.

Source: mart_daily_air_quality.
*/

{{ config(
    materialized      = 'table',
    partitioned_by    = [],
    format            = 'parquet',
    write_compression = 'snappy'
) }}

select
    city,
    province,
    measurement_date,
    avg(avg_value) as pm25_city_avg

from {{ ref('mart_daily_air_quality') }}
where parameter = 'pm25'
  and is_outlier_station = 0

group by city, province, measurement_date

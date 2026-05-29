/*
mart_health_summary — annual health day counts and WHO compliance per city.

Grain: city × year

This mart drives the "Health Day Counts" and "WHO compliance %" visuals in
QuickSight Sheet 1 and the calendar heatmap annotation layer.

Key metrics:
  - {category}_days    : count of days where PM2.5 composite fell in each AQI band
  - who_compliant_days : days where PM2.5 daily avg ≤ 15 µg/m³ (WHO AQG 2021)
  - who_compliance_pct : who_compliant_days / total_days × 100
  - avg_cigarette_equivalent : average daily cigarette exposure (avg_pm25 / 22 µg/m³)

Storytelling reference values (from aqi.in survey, 2026 YTD):
  Hanoi  → who_compliance_pct ≈ 2%,  risk_label "Extreme"
  HCMC   → who_compliance_pct ≈ 37%, risk_label "High"

Note: aggregated at city level (avg across all reference stations per city per day)
so that multi-station cities (Hanoi: 16 stations) are not double-counted.
One representative daily avg per city per day is derived as the mean of all
station avg_values for that parameter and date.
*/

{{ config(materialized = 'table', partitioned_by = [], format = 'parquet', write_compression = 'snappy', tags = ['bi_disabled']) }}

with city_daily as (

    -- City-level daily PM2.5 average (multi-station collapse) sourced from the
    -- shared int_city_daily_pm25 model. pm25_city_avg arrives unrounded; this
    -- mart re-applies the historical round(..., 4) and derives its day-level
    -- health flags exactly as before.
    select
        city,
        province,
        measurement_date,
        year(measurement_date)              as year,
        round(pm25_city_avg, 4)             as pm25_city_avg,
        round(pm25_city_avg / 22.0, 2)      as cigarette_equivalent,
        cast(pm25_city_avg <= 15 as int)    as who_compliant_day,

        -- City-level AQI category derived from the city daily avg (shared macro)
        {{ get_aqi_category("'pm25'", 'pm25_city_avg') }} as aqi_category

    from {{ ref('int_city_daily_pm25') }}

),

-- Aggregate into a subquery so risk_label can reference who_compliance_pct
-- without repeating the count_if expression three times in the CASE branches.
aggregated as (

    select
        city,
        province,
        year,

        count(*)                                            as total_days,

        -- Health day counts
        count_if(aqi_category = 'Good')                     as good_days,
        count_if(aqi_category = 'Moderate')                 as moderate_days,
        count_if(aqi_category = 'Unhealthy for Sensitive Groups') as usg_days,
        count_if(aqi_category = 'Unhealthy')                as unhealthy_days,
        count_if(aqi_category = 'Very Unhealthy')           as very_unhealthy_days,
        count_if(aqi_category = 'Hazardous')                as hazardous_days,

        -- WHO compliance
        count_if(who_compliant_day = 1)                     as who_compliant_days,
        round(
            100.0 * count_if(who_compliant_day = 1) / count(*), 1
        )                                                   as who_compliance_pct,

        -- Health exposure
        round(avg(pm25_city_avg), 1)                        as avg_pm25,
        round(avg(cigarette_equivalent), 2)                 as avg_cigarette_equivalent,
        round(max(pm25_city_avg), 1)                        as max_pm25

    from city_daily
    group by city, province, year

)

select
    city,
    province,
    year,
    total_days,
    good_days,
    moderate_days,
    usg_days,
    unhealthy_days,
    very_unhealthy_days,
    hazardous_days,
    who_compliant_days,
    who_compliance_pct,
    avg_pm25,
    avg_cigarette_equivalent,
    max_pm25,

    -- Risk label references who_compliance_pct alias — single evaluation
    case
        when who_compliance_pct >= 80 then 'Low'
        when who_compliance_pct >= 50 then 'Moderate'
        when who_compliance_pct >= 20 then 'High'
        else 'Extreme'
    end as risk_label

from aggregated

/*
mart_monthly_profile — average pollutant concentration by month of year.

Grain: location_id × parameter × month_of_year (1–12)

Answers: "Which months are worst for PM2.5 in Hanoi?"

Vietnam seasonal context (PM2.5):
  Nov–Mar : Worst  — NE monsoon temperature inversions, low boundary layer,
                     long-range transport from southern China
  Apr–May : Elevated — rice straw biomass burning in surrounding delta areas
  Jun–Sep : Best   — SW monsoon rains wash aerosols out; strong convective mixing
  Oct–Nov : Rising — pre-winter accumulation as monsoon retreats

Use in dashboard:
  - Bar/line chart: X = month (Jan–Dec), Y = avg_value, series = city
    → clearly shows winter peak vs. summer clean season
  - Heatmap combined with mart_diurnal_profile: hour × month colour map
*/

{{ config(materialized = 'table') }}

select
    location_id,
    location_name,
    city,
    province,
    sensor_type,
    parameter,
    month(measurement_date)                 as month_of_year,
    round(avg(measurement_value), 4)        as avg_value,
    round(max(measurement_value), 4)        as max_value,
    round(min(measurement_value), 4)        as min_value,
    round(
        approx_percentile(measurement_value, 0.95), 4
    )                                       as p95_value,
    count(*)                                as reading_count,
    count(distinct cast(measurement_date as varchar)) as day_count

from {{ ref('int_measurements_enriched') }}

group by
    location_id,
    location_name,
    city,
    province,
    sensor_type,
    parameter,
    month(measurement_date)

order by city, parameter, month_of_year

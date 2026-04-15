/*
mart_pollutant_ratio — daily PM2.5 / PM10 ratio per station as a pollution source indicator.

Grain: location_id × measurement_date

Source: mart_daily_air_quality pivoted via conditional aggregation (MAX CASE WHEN).
Outlier station 6273386 excluded.

PM2.5/PM10 ratio interpretation (literature-validated thresholds):
  > 0.7  → 'combustion-dominated' — exhaust particulates from traffic or biomass burning
             produce fine particles (PM2.5) with little coarse fraction (PM10–PM2.5).
             Hanoi dry-season values typically 0.65–0.75 (NE monsoon + traffic).
  0.4–0.7 → 'mixed' — combination of combustion and resuspended road/soil dust.
  < 0.4  → 'crustal/dust' — road dust, construction, soil resuspension dominate;
             coarse fraction (PM10–PM2.5) >> fine fraction.

Use in dashboard:
  - Bar chart: X = station, Y = pm25_pm10_ratio, colour = source_indicator
    → which Hanoi stations are most combustion-driven vs dust-driven?
  - Faceted by season: NE monsoon (combustion peak) vs SW monsoon (lower ratio)
  - Scatter: X = pm10_avg, Y = pm25_avg, colour = source_indicator
    → visualises the three source regimes as clusters

Note: NULL rows are retained in the mart (station reported only one pollutant on that date)
so that aggregating by location_id still yields complete coverage for pm25_avg/pm10_avg
even when the ratio cannot be computed.
*/

{{ config(materialized = 'table', partitioned_by = [], format = 'parquet', write_compression = 'snappy') }}

select
    location_id,
    location_name,
    city,
    province,
    measurement_date,

    -- Conditional aggregation pivot: one row per station-day with all pollutants
    round(max(case when parameter = 'pm25' then avg_value end), 4) as pm25_avg,
    round(max(case when parameter = 'pm10' then avg_value end), 4) as pm10_avg,
    -- pm1 is reported by AirGradient low-cost sensors only; NULL for reference stations.
    -- pm1/pm25 ratio < 0.7 → secondary aerosol (ammonium sulfate/nitrate) dominant;
    -- pm1/pm25 ratio > 0.85 → fresh combustion particles dominant.
    round(max(case when parameter = 'pm1'  then avg_value end), 4) as pm1_avg,

    -- Ratio: NULL when either pollutant is missing or PM10 is zero
    case
        when max(case when parameter = 'pm25' then avg_value end) is null
          or max(case when parameter = 'pm10' then avg_value end) is null
          or max(case when parameter = 'pm10' then avg_value end) = 0
            then null
        else round(
            max(case when parameter = 'pm25' then avg_value end) /
            max(case when parameter = 'pm10' then avg_value end),
            4
        )
    end as pm25_pm10_ratio,

    -- Source indicator derived from ratio
    case
        when max(case when parameter = 'pm25' then avg_value end) is null
          or max(case when parameter = 'pm10' then avg_value end) is null
          or max(case when parameter = 'pm10' then avg_value end) = 0
            then null
        when max(case when parameter = 'pm25' then avg_value end) /
             max(case when parameter = 'pm10' then avg_value end) > 0.7
            then 'combustion-dominated'
        when max(case when parameter = 'pm25' then avg_value end) /
             max(case when parameter = 'pm10' then avg_value end) >= 0.4
            then 'mixed'
        else 'crustal/dust'
    end as source_indicator

from {{ ref('mart_daily_air_quality') }}
where parameter in ('pm25', 'pm10', 'pm1')
  and is_outlier_station = 0

group by
    location_id,
    location_name,
    city,
    province,
    measurement_date
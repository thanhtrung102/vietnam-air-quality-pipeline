/*
mart_daily_meteorology — daily temperature and relative humidity per station.

Grain: location_id × measurement_date

Source: int_measurements_enriched WHERE parameter IN ('relativehumidity', 'temperature')
Station 6273386 (VNUHCMUS Campus 1) excluded — outlier artefact readings.

Coverage note:
  Only AirGradient low-cost optical sensors report T/RH. As of 2026-03-25 only
  two stations contribute data (4,678 readings each in the full dataset):
    6123215 — OceanPark, Hanoi-adjacent (active Nov 2025–present)
    6068138 — Care Centre, HCMC (active Oct–Dec 2025)
  The T/RH fields will be NULL for all other stations (reference FEM monitors do
  not report meteorological parameters via OpenAQ).

Use in dashboard:
  - Scatter: T vs PM2.5 (join to mart_daily_air_quality on location_id + date)
    → shows negative correlation: SW monsoon high-T → low PM2.5 (wet scavenging)
  - Time series: avg_rh overlaid on PM2.5 time series at low-cost stations
    → validates hygroscopic growth hypothesis (high RH → overestimated raw PM2.5)
  - Inversion proxy: join to mart_daily_weather (Phase 3) for BLH comparison

Partitioned by measurement_date for efficient date-filtered joins to
mart_daily_air_quality (same partition key).
*/

{{ config(materialized = 'table', partitioned_by = ['measurement_date'], format = 'parquet', write_compression = 'snappy') }}

select
    location_id,
    location_name,
    city,
    province,
    sensor_type,
    measurement_date,

    -- Temperature (°C) — daily statistics
    round(avg(case when parameter = 'temperature'      then measurement_value end), 4) as avg_temperature,
    round(max(case when parameter = 'temperature'      then measurement_value end), 4) as max_temperature,
    round(min(case when parameter = 'temperature'      then measurement_value end), 4) as min_temperature,
    count(case when parameter = 'temperature'          then 1                  end)    as reading_count_temperature,

    -- Relative humidity (%) — daily statistics
    round(avg(case when parameter = 'relativehumidity' then measurement_value end), 4) as avg_rh,
    round(max(case when parameter = 'relativehumidity' then measurement_value end), 4) as max_rh,
    round(min(case when parameter = 'relativehumidity' then measurement_value end), 4) as min_rh,
    count(case when parameter = 'relativehumidity'     then 1                  end)    as reading_count_rh

from {{ ref('int_measurements_enriched') }}
where parameter in ('relativehumidity', 'temperature')
  and location_id != 6273386  -- outlier station: artefact readings from Mar 2026 startup

group by
    location_id,
    location_name,
    city,
    province,
    sensor_type,
    measurement_date

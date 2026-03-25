/*
mart_daily_air_quality — daily aggregated air quality metrics by station and pollutant.

Materialised as a partitioned Athena/Iceberg table:
  partition by: measurement_date
  bucketed by:  parameter, location_id (for efficient pollutant/station queries)

Sources: stg_openaq_batch ∪ stg_openaq_stream
Grain:   one row per (measurement_date, location_id, parameter)

Columns:
  measurement_date  — UTC calendar date of readings (partition key)
  location_id       — OpenAQ station ID
  location_name     — Human-readable station name (most-frequent value in the day)
  lat / lon         — Station coordinates (most-frequent value; stable per station)
  parameter         — Pollutant code (pm25, pm10, no2, o3, co, so2, bc)
  units             — Measurement units (µg/m³, ppm, ppb)
  reading_count     — Number of valid readings in the day (excludes -999.0)
  avg_value         — Daily mean concentration
  max_value         — Daily maximum concentration
  min_value         — Daily minimum concentration
  p95_value         — 95th-percentile concentration (for health-episode flagging)
  source_types      — Comma-separated list of data sources contributing to this row
*/

with

batch as (
    select * from {{ ref('stg_openaq_batch') }}
),

stream as (
    select * from {{ ref('stg_openaq_stream') }}
),

combined as (

    select
        measurement_date,
        location_id,
        location,
        lat,
        lon,
        parameter,
        units,
        value,
        source_type
    from batch

    union all

    select
        measurement_date,
        location_id,
        location,
        lat,
        lon,
        parameter,
        units,
        value,
        source_type
    from stream

),

aggregated as (

    select
        measurement_date,
        location_id,

        -- Most-frequent location name and coordinates for the day
        -- (max() gives a deterministic result without a subquery in Presto/Athena)
        max(location)   as location_name,
        max(lat)        as lat,
        max(lon)        as lon,

        parameter,
        max(units)      as units,

        count(*)                                as reading_count,
        round(avg(value),   2)                  as avg_value,
        round(max(value),   2)                  as max_value,
        round(min(value),   2)                  as min_value,
        round(
            approx_percentile(value, 0.95),
            2
        )                                       as p95_value,

        array_join(
            array_agg(distinct source_type),
            ','
        )                                       as source_types

    from combined

    group by
        measurement_date,
        location_id,
        parameter

)

select * from aggregated

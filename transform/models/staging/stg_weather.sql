/*
stg_weather — staging view over the weather external Glue table.

Source: openaq_raw.weather
  - Written by the weather_ingest Lambda (Open-Meteo ERA5 hourly reanalysis)
  - Path: raw/weather/{location_id}/{yyyy}/{MM}/{dd}/weather.ndjson
  - Grain: one row per location_id × date × hour_utc (24 rows/station/day)

Transformations:
  - Cast date string → DATE, hour_utc → INT
  - Cast all weather values to DOUBLE
  - Derive measurement_date from date column (partition key alignment)
  - Filter null rows that Open-Meteo may emit for hours with missing ERA5 data
    (rare; typically affects only the most recent day in the reanalysis lag window)

Note: location_id is a Glue partition key (int). It is already correctly typed
      by the Glue schema; no explicit CAST needed, but round-trip through
      source() may return it as string — CAST defensively.
*/

with source as (

    select
        location_id,
        date,
        hour_utc,
        temperature_2m,
        rh_2m,
        wind_speed,
        wind_dir,
        precipitation_mm,
        surface_pressure_hpa,
        boundary_layer_height_m

    from {{ source('openaq_raw', 'weather') }}

    where date         is not null
      and hour_utc     is not null
      and temperature_2m is not null

),

typed as (

    select
        cast(location_id          as int)    as location_id,
        cast(date                 as date)   as measurement_date,
        cast(hour_utc             as int)    as hour_utc,
        round(cast(temperature_2m      as double), 4) as temperature_2m,
        round(cast(rh_2m               as double), 2) as rh_2m,
        round(cast(wind_speed          as double), 4) as wind_speed,
        round(cast(wind_dir            as double), 2) as wind_dir,
        round(cast(precipitation_mm    as double), 4) as precipitation_mm,
        round(cast(surface_pressure_hpa as double), 2) as surface_pressure_hpa,
        round(cast(boundary_layer_height_m as double), 1) as boundary_layer_height_m

    from source

)

select * from typed

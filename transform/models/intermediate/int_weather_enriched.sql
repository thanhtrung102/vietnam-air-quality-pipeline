/*
int_weather_enriched — hourly weather enriched with station metadata.

Source: stg_weather (hourly ERA5) + vn_stations (seed)

Transformations:
  - Inner join on location_id to add city, province, location_name.
  - Only the 21 known stations in the seed are in scope; any unexpected
    location_id written by the Lambda is implicitly excluded.
  - Preserves hourly grain from stg_weather for flexible downstream aggregation.
*/

with weather as (

    select * from {{ ref('stg_weather') }}

),

stations as (

    select
        location_id,
        location_name,
        city,
        province,
        latitude,
        longitude,
        sensor_type

    from {{ ref('vn_stations') }}

),

enriched as (

    select
        w.location_id,
        w.measurement_date,
        w.hour_utc,
        w.temperature_2m,
        w.rh_2m,
        w.wind_speed,
        w.wind_dir,
        w.precipitation_mm,
        w.surface_pressure_hpa,
        w.boundary_layer_height_m,

        s.location_name,
        s.city,
        s.province,
        s.sensor_type

    from weather w
    inner join stations s on w.location_id = s.location_id

)

select * from enriched

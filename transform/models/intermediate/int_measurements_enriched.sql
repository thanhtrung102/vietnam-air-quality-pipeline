/*
int_measurements_enriched — staging measurements joined with station metadata.

Source: stg_measurements (staging view) + vn_stations (seed)

Transformations:
  - Left join vn_stations on location_id to add city, province, and
    canonical station coordinates (station_lat, station_lon, location_name)
  - Filter WHERE city IS NOT NULL
    -- Excludes station IDs not in vn_stations seed (no city mapping available)
*/

with measurements as (

    select * from {{ ref('stg_measurements') }}

),

stations as (

    select
        location_id,
        location_name,
        city,
        province,
        latitude,
        longitude

    from {{ ref('vn_stations') }}

),

enriched as (

    select
        m.location_id,
        m.sensor_id,
        m.location,
        m.measured_at,
        m.measurement_date,
        m.lat,
        m.lon,
        m.parameter,
        m.units,
        m.measurement_value,

        s.location_name,
        s.city,
        s.province,
        s.latitude  as station_lat,
        s.longitude as station_lon

    from measurements m
    left join stations s on m.location_id = s.location_id

)

select * from enriched
where city is not null
-- Excludes station IDs not in vn_stations seed (no city mapping available)

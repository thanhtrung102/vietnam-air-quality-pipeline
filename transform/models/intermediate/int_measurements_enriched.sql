/*
int_measurements_enriched — staging measurements joined with station metadata.

Source: stg_measurements (staging view) + vn_stations (seed)

Transformations:
  - Left join vn_stations on location_id to add city, province,
    canonical station coordinates (station_lat, station_lon, location_name),
    and sensor_type (reference | low_cost)
  - Filter WHERE city IS NOT NULL
    -- Excludes station IDs not in vn_stations seed (no city mapping available)
  - sensor_type='low_cost' stations (6123215, 6068138, 6273386) are AirGradient
    optical sensors. Diagnostic confirmed all stations read within expected ranges
    after filtering sentinel value 985.0 in staging; no flat correction applied.
    sensor_type is retained for downstream filtering and future RH-based
    EPA correction (requires self-join on relativehumidity parameter).
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
        longitude,
        sensor_type

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
        s.latitude   as station_lat,
        s.longitude  as station_lon,
        s.sensor_type

    from measurements m
    left join stations s on m.location_id = s.location_id

)

select * from enriched
where city is not null
-- Excludes station IDs not in vn_stations seed (no city mapping available)

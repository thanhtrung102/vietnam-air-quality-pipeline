/*
int_measurements_enriched — staging measurements joined with station metadata.

Source: stg_measurements (staging view) + vn_stations (seed)

Transformations:
  - Inner join vn_stations on location_id to add city, province,
    canonical station coordinates (station_lat, station_lon, location_name),
    and sensor_type (reference | low_cost). Only the 21 stations in the seed
    are in scope; unrecognised location_ids are implicitly excluded.
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

    -- INNER JOIN: vn_stations is the authoritative station allowlist.
    -- Only the 21 known Vietnamese stations are in scope; any location_id not
    -- present in the seed is excluded. Using LEFT JOIN + WHERE city IS NOT NULL
    -- is semantically equivalent but prevents the planner from using an optimised
    -- broadcast hash join on the 21-row seed table.
    from measurements m
    inner join stations s on m.location_id = s.location_id

)

select * from enriched

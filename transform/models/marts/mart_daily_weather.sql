/*
mart_daily_weather — daily weather aggregates per station.

Source: int_weather_enriched (hourly ERA5 weather + station metadata)
Grain:  one row per location_id × measurement_date

Aggregations:
  - Temperature: avg/max/min across 24 UTC hours
  - Relative humidity: avg/max/min
  - Wind speed: avg (daily mean); calm_wind_hours = hours where wind_speed < 2 m/s
  - Wind direction: not aggregated (circular mean requires trigonometry beyond
    this mart's scope; avg_wind_dir is a simple numeric average — use with care)
  - Precipitation: sum (daily total in mm)
  - Surface pressure: avg
  - Boundary layer height: avg and min (min captures morning inversion peak)

Derived flags (used in mart_aq_weather_daily):
  - inversion_risk:   min_boundary_layer_height_m < 500 AND avg_wind_speed < 2.0
                      Shallow BLH traps surface-emitted pollutants; calm winds
                      prevent lateral dilution. Combined flag indicates high
                      probability of PM2.5 accumulation episode.
  - wet_scavenging:   total_precipitation_mm > 5.0
                      > 5 mm/day removes a meaningful fraction of PM2.5 via
                      below-cloud scavenging; threshold from literature (Xu et al., 2017).

Partition strategy: measurement_date (aligns with mart_daily_air_quality).
*/

{{ config(
    materialized      = 'table',
    partitioned_by    = ['measurement_date'],
    format            = 'parquet',
    write_compression = 'snappy'
) }}

with source as (

    select * from {{ ref('int_weather_enriched') }}

),

daily as (

    select
        location_id,
        location_name,
        city,
        province,
        sensor_type,

        round(avg(temperature_2m),          4) as avg_temperature_2m,
        round(max(temperature_2m),          4) as max_temperature_2m,
        round(min(temperature_2m),          4) as min_temperature_2m,

        round(avg(rh_2m),                   2) as avg_rh_2m,
        round(max(rh_2m),                   2) as max_rh_2m,
        round(min(rh_2m),                   2) as min_rh_2m,

        round(avg(wind_speed),              4) as avg_wind_speed,
        round(avg(wind_dir),                2) as avg_wind_dir,
        count(case when wind_speed < 2.0 then 1 end) as calm_wind_hours,

        round(sum(precipitation_mm),        4) as total_precipitation_mm,

        round(avg(surface_pressure_hpa),    2) as avg_surface_pressure_hpa,

        round(avg(boundary_layer_height_m), 1) as avg_boundary_layer_height_m,
        round(min(boundary_layer_height_m), 1) as min_boundary_layer_height_m,

        count(*) as reading_count_hours,

        -- partition column must be last
        measurement_date

    from source
    group by
        measurement_date,
        location_id,
        location_name,
        city,
        province,
        sensor_type

)

select
    location_id,
    location_name,
    city,
    province,
    sensor_type,
    avg_temperature_2m,
    max_temperature_2m,
    min_temperature_2m,
    avg_rh_2m,
    max_rh_2m,
    min_rh_2m,
    avg_wind_speed,
    avg_wind_dir,
    calm_wind_hours,
    total_precipitation_mm,
    avg_surface_pressure_hpa,
    avg_boundary_layer_height_m,
    min_boundary_layer_height_m,
    reading_count_hours,

    -- Inversion risk: shallow boundary layer + calm winds trap pollutants.
    -- min BLH < 500 m: morning inversion not yet broken up by daytime mixing.
    -- avg wind < 2 m/s: insufficient lateral dispersion.
    cast(
        min_boundary_layer_height_m < 500.0
        and avg_wind_speed           < 2.0
    as int) as inversion_risk,

    -- Wet scavenging: daily precipitation > 5 mm removes surface PM2.5.
    -- Flag used in mart_aq_weather_daily to identify natural washout days.
    cast(total_precipitation_mm > 5.0 as int) as wet_scavenging,

    measurement_date

from daily

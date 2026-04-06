/*
mart_aq_weather_daily — air quality joined to weather covariates, daily grain.

Source:
  - mart_daily_air_quality  (pm25 rows only, outlier station excluded)
  - mart_daily_weather      (ERA5 daily aggregates per station)

Grain: one row per location_id × measurement_date (pm25 grain from AQ side)

Join type: LEFT JOIN from AQ to weather.
  Weather may be absent for a given day if the weather_ingest Lambda failed
  or the ERA5 reanalysis lag has not yet published the data. LEFT JOIN ensures
  the AQ record is still present; all weather columns will be NULL in that case.
  Use WHERE avg_wind_speed IS NOT NULL to restrict to matched rows.

Derived diagnostics (carried over from mart_daily_weather):
  - inversion_risk (0/1): min_blh < 500 m AND avg_wind_speed < 2 m/s
  - wet_scavenging (0/1): total_precipitation_mm > 5 mm/day

Outlier exclusion: is_outlier_station = 0 (station 6273386 excluded).

Partition strategy: measurement_date (aligns with both source marts).
*/

{{ config(
    materialized      = 'table',
    partitioned_by    = ['measurement_date'],
    format            = 'parquet',
    write_compression = 'snappy'
) }}

with aq as (

    select
        location_id,
        location_name,
        city,
        province,
        sensor_type,
        avg_value          as avg_pm25,
        max_value          as max_pm25,
        corrected_pm25,
        aqi_value,
        aqi_category,
        exceeds_who_24h,
        exceeds_qcvn,
        cigarette_equivalent,
        is_outlier_station,
        measurement_date

    from {{ ref('mart_daily_air_quality') }}

    where parameter          = 'pm25'
      and is_outlier_station = 0

),

weather as (

    select
        location_id,
        measurement_date,
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
        inversion_risk,
        wet_scavenging

    from {{ ref('mart_daily_weather') }}

),

joined as (

    select
        a.location_id,
        a.location_name,
        a.city,
        a.province,
        a.sensor_type,
        a.avg_pm25,
        a.max_pm25,
        a.corrected_pm25,
        a.aqi_value,
        a.aqi_category,
        a.exceeds_who_24h,
        a.exceeds_qcvn,
        a.cigarette_equivalent,

        -- Weather covariates (NULL when weather fetch failed for this date/station)
        w.avg_temperature_2m,
        w.max_temperature_2m,
        w.min_temperature_2m,
        w.avg_rh_2m,
        w.max_rh_2m,
        w.min_rh_2m,
        w.avg_wind_speed,
        w.avg_wind_dir,
        w.calm_wind_hours,
        w.total_precipitation_mm,
        w.avg_surface_pressure_hpa,
        w.avg_boundary_layer_height_m,
        w.min_boundary_layer_height_m,

        -- Derived pollution-meteorology flags
        w.inversion_risk,
        w.wet_scavenging,

        -- partition column must be last
        a.measurement_date

    from aq a
    left join weather w
           on a.location_id      = w.location_id
          and a.measurement_date = w.measurement_date

)

select * from joined

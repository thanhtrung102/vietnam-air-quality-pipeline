/*
stg_measurements — staging view over the unified raw_measurements external table.

Source: openaq_raw.raw_measurements (partition-projected Athena external table,
        raw/batch/ prefix, OpenCSVSerde handles quoted and unquoted CSV rows).

Transformations:
  - sensors_id → sensor_id (consistent naming for downstream models)
  - value → measurement_value (explicit name for the numeric measurement)
  - datetime string → measured_at TIMESTAMP via from_iso8601_timestamp()
    (handles +07:00 timezone offset; date_parse does not support timezone offsets)
  - measurement_date derived from measured_at for mart partitioning
  - location_id cast to INT
  - lon rounded to 6 dp (floating-point noise observed in station 4946812)
  - Filters (ALL parameters): null datetime/value/parameter/location_id,
             sentinel -999.0, negative values.
  - Filter (pm25 ONLY): value >= 500. Station 7440 emits 985.0 as a fill/error
             code, and 500 µg/m³ is the US EPA PM2.5 AQI ceiling — physically
             implausible as a sustained PM2.5 concentration. This ceiling is
             intentionally NOT applied to other parameters: PM10 legitimately
             exceeds 500 µg/m³ during dust/haze events, so a blanket ceiling
             would silently drop valid high-PM10 readings.
*/

with source as (

    select
        location_id,
        sensors_id,
        location,
        datetime,
        lat,
        lon,
        parameter,
        units,
        value

    from {{ source('openaq_raw', 'batch') }}

    where datetime        is not null
      and value           is not null
      and value           != -999.0
      and value           >= 0
      -- pm25-specific ceiling: filter fill/error code 985.0 (station 7440) and
      -- physically implausible sustained PM2.5. Other parameters (e.g. pm10 during
      -- dust events) may legitimately exceed 500 µg/m³, so the ceiling is scoped.
      and not (lower(parameter) = 'pm25' and value >= 500)
      and parameter       is not null
      and location_id     is not null

),

renamed as (

    select
        cast(location_id as int)                        as location_id,
        cast(sensors_id  as int)                        as sensor_id,
        location,

        -- Timezone-aware cast: from_iso8601_timestamp handles +07:00 offsets
        cast(from_iso8601_timestamp(datetime) as timestamp) as measured_at,
        cast(from_iso8601_timestamp(datetime) as date)      as measurement_date,

        round(cast(lat as double), 6)                   as lat,
        round(cast(lon as double), 6)                   as lon,

        lower(parameter)                                as parameter,
        units,
        cast(value as double)                           as measurement_value

    from source

)

select * from renamed

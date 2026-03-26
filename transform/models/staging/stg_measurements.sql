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
  - Filters: nulls, sentinel -999.0, negative values, null parameter,
             values >= 500 (station 7440 emits 985.0 as a fill/error code;
             500 µg/m³ is the US EPA AQI ceiling and physically implausible
             as a sustained PM2.5 concentration)
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

    from {{ source('openaq_raw', 'raw_measurements') }}

    where datetime        is not null
      and value           is not null
      and value           != -999.0
      and value           >= 0
      and value           < 500    -- filter fill/error code 985.0 from station 7440
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

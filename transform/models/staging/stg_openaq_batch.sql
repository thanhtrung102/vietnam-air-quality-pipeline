/*
stg_openaq_batch — staging view over the historical + daily-incremental batch data.

Source: openaq_raw.batch (Hive-partitioned CSV.GZ, Partition Projection enabled)

Transformations applied:
  - Filter sentinel value -999.0 (missing/invalid readings)
  - Cast datetime string → TIMESTAMP WITH TIME ZONE using from_iso8601_timestamp()
  - Extract UTC date as measurement_date for partitioning the mart
  - Round lat/lon to 6 decimal places (raw lon has floating-point noise)
  - Normalise value to DOUBLE
  - Add source_type = 'batch' for traceability in the mart UNION ALL
  - ingested_at is NULL for batch (archive files have no ingest timestamp)
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

    where value != -999.0

),

renamed as (

    select
        cast(location_id as integer)  as location_id,
        cast(sensors_id  as integer)  as sensors_id,
        location,

        -- Athena requires from_iso8601_timestamp() for timezone-aware strings (+07:00)
        from_iso8601_timestamp(datetime)        as measurement_ts,
        date(from_iso8601_timestamp(datetime))  as measurement_date,

        round(cast(lat as double), 6)   as lat,
        round(cast(lon as double), 6)   as lon,

        lower(parameter)    as parameter,
        units,
        cast(value as double)           as value,

        cast(null as varchar)           as ingested_at,
        'batch'                         as source_type

    from source

)

select * from renamed

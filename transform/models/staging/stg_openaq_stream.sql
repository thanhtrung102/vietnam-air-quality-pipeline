/*
stg_openaq_stream — staging view over the near-real-time stream data.

Source: openaq_raw.stream (NDJSON from Kinesis Firehose, Partition Projection enabled)

Transformations applied:
  - Filter sentinel value -999.0
  - Cast datetime string (UTC ISO-8601 from OpenAQ /latest endpoint) → TIMESTAMP
  - Extract UTC date as measurement_date
  - Round lat/lon to 6 decimal places (consistency with batch staging)
  - Normalise value to DOUBLE
  - Add source_type = 'stream' for traceability in the mart UNION ALL
  - ingested_at preserved as-is (written by kinesis_producer at ingest time)
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
        value,
        ingested_at

    from {{ source('openaq_raw', 'stream') }}

    where value != -999.0

),

renamed as (

    select
        cast(location_id as integer)    as location_id,
        cast(sensors_id  as integer)    as sensors_id,
        location,

        -- Stream datetimes are UTC ISO-8601 without timezone offset
        from_iso8601_timestamp(datetime)        as measurement_ts,
        date(from_iso8601_timestamp(datetime))  as measurement_date,

        round(cast(lat as double), 6)   as lat,
        round(cast(lon as double), 6)   as lon,

        lower(parameter)    as parameter,
        units,
        cast(value as double)           as value,

        ingested_at,
        'stream'                        as source_type

    from source

)

select * from renamed

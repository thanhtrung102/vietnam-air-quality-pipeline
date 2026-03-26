/*
mart_daily_air_quality — daily aggregated air quality metrics per station and pollutant.

Partition / bucketing strategy:
  - partition key: measurement_date
      Every dashboard query filters on a date range; partitioning on
      measurement_date means Athena reads only the relevant date partitions
      and skips all other data, minimising scan cost and query latency.
  - bucket keys: parameter, location_id (bucket_count=8)
      These are the most common secondary filter dimensions — users typically
      query one pollutant for one or a small set of stations. Bucketing on
      both columns co-locates matching rows within each date partition,
      enabling efficient equality and small-range predicates on parameter
      and location_id without a full partition scan.

Note: measurement_date must be the last column in the SELECT because Athena/Hive
requires partition columns to appear at the end of the table definition.

Grain: one row per measurement_date × location_id × parameter.
Source: int_measurements_enriched (staging measurements + station metadata).
*/

{{ config(
    materialized   = 'table',
    partitioned_by = ['measurement_date']
) }}

with source as (

    select * from {{ ref('int_measurements_enriched') }}

),

aggregated as (

    select
        city,
        province,
        parameter,
        location_id,
        location_name,
        station_lat,
        station_lon,

        round(avg(measurement_value), 4)  as avg_value,
        round(max(measurement_value), 4)  as max_value,
        round(min(measurement_value), 4)  as min_value,
        count(*)                          as reading_count,
        count(distinct sensor_id)         as sensor_count,

        -- partition column must be last
        measurement_date

    from source

    group by
        measurement_date,
        city,
        province,
        parameter,
        location_id,
        location_name,
        station_lat,
        station_lon

)

select * from aggregated
order by measurement_date desc, city, parameter

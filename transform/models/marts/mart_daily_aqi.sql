/*
mart_daily_aqi — composite AQI per station per day.

Grain: one row per measurement_date × location_id.

The composite AQI is the maximum individual-pollutant AQI across all
parameters reported for that station on that day (US EPA methodology).
The dominant_pollutant is whichever parameter produced the composite AQI.

Currently PM2.5 and PM10 contribute to the composite.
O3/NO2/SO2/CO are excluded pending unit normalisation in staging
(OpenAQ reports these in µg/m³; EPA breakpoints use ppm/ppb and
sub-daily averaging windows).

Additional columns:
  - pm25_avg            : raw PM2.5 daily average (µg/m³) for the station, for reference context
  - cigarette_equivalent: pm25_avg / 22.0 — how many cigarettes/day this exposure represents
                          (Berkeley Earth / aqi.in standard: 1 cigarette ≈ 22 µg/m³ PM2.5/day)
  - NULL for both if the station reported no PM2.5 on that date

health_category follows the US EPA 2024 AQI breakpoints:
  Good (0–50) | Moderate (51–100) | Unhealthy for Sensitive Groups (101–150)
  Unhealthy (151–200) | Very Unhealthy (201–300) | Hazardous (301–500)
*/

{{ config(
    materialized   = 'table',
    partitioned_by = ['measurement_date']
) }}

-- Single scan of mart_daily_air_quality. The former pm25_daily CTE was a
-- redundant second full-table scan. PM2.5 context (pm25_avg, cigarette_equivalent)
-- is now extracted in the composite CTE using conditional aggregation, which
-- correctly handles both cases: PM2.5-dominant and PM10-dominant stations.
with per_pollutant as (

    select
        measurement_date,
        location_id,
        location_name,
        city,
        province,
        station_lat,
        station_lon,
        sensor_type,
        parameter,
        avg_value,
        aqi_value,
        aqi_category,
        cigarette_equivalent

    from {{ ref('mart_daily_air_quality') }}
    where aqi_value is not null

),

-- Composite AQI = max individual AQI for this station on this date.
-- PM2.5 context columns extracted here via conditional aggregation so no
-- second scan is needed regardless of which pollutant drives the composite.
composite as (

    select
        measurement_date,
        location_id,
        location_name,
        city,
        province,
        station_lat,
        station_lon,
        sensor_type,
        max(aqi_value)                                              as composite_aqi,
        max(case when parameter = 'pm25' then avg_value end)        as pm25_avg,
        max(case when parameter = 'pm25' then cigarette_equivalent end) as cigarette_equivalent

    from per_pollutant
    group by
        measurement_date,
        location_id,
        location_name,
        city,
        province,
        station_lat,
        station_lon,
        sensor_type

),

-- Join back to identify the dominant pollutant that drove the composite AQI
with_dominant as (

    select
        c.measurement_date,
        c.location_id,
        c.location_name,
        c.city,
        c.province,
        c.station_lat,
        c.station_lon,
        c.sensor_type,
        c.composite_aqi,
        c.pm25_avg,
        c.cigarette_equivalent,
        -- If two pollutants tie, PM2.5 takes precedence (stricter health relevance)
        max_by(p.parameter, p.aqi_value)    as dominant_pollutant,
        max_by(p.aqi_category, p.aqi_value) as health_category

    from composite c
    join per_pollutant p
        on  c.measurement_date = p.measurement_date
        and c.location_id      = p.location_id
        and c.composite_aqi    = p.aqi_value

    group by
        c.measurement_date,
        c.location_id,
        c.location_name,
        c.city,
        c.province,
        c.station_lat,
        c.station_lon,
        c.sensor_type,
        c.composite_aqi,
        c.pm25_avg,
        c.cigarette_equivalent

)

select
    city,
    province,
    location_id,
    location_name,
    station_lat,
    station_lon,
    sensor_type,
    composite_aqi,
    dominant_pollutant,
    health_category,
    pm25_avg,
    cigarette_equivalent,
    -- partition column last
    measurement_date

from with_dominant

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

health_category follows the US EPA 2024 AQI breakpoints:
  Good (0–50) | Moderate (51–100) | Unhealthy for Sensitive Groups (101–150)
  Unhealthy (151–200) | Very Unhealthy (201–300) | Hazardous (301–500)
*/

{{ config(
    materialized   = 'table',
    partitioned_by = ['measurement_date']
) }}

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
        aqi_category

    from {{ ref('mart_daily_air_quality') }}
    where aqi_value is not null

),

-- Composite AQI = max individual AQI for this station on this date
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
        max(aqi_value) as composite_aqi

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
        -- If two pollutants tie, PM2.5 takes precedence (stricter health relevance)
        max_by(p.parameter, p.aqi_value)  as dominant_pollutant,
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
        c.composite_aqi

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
    -- partition column last
    measurement_date

from with_dominant
order by measurement_date desc, city

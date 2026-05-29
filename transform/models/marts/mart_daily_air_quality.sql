/*
mart_daily_air_quality — daily aggregated air quality metrics per station and pollutant.

Partition strategy:
  - partition key: measurement_date
      Every dashboard query filters on a date range; partitioning on
      measurement_date means Athena reads only the relevant date partitions,
      minimising scan cost and query latency.

Note: measurement_date must be the last column in the SELECT because Athena/Hive
requires partition columns to appear at the end of the table definition.

AQI calculation:
  - Computed only for parameter = 'pm25' using US EPA 2024 updated breakpoints
    (annual NAAQS lowered from 12.0 to 9.0 µg/m³ in May 2024).
  - Piecewise linear interpolation: AQI = ((I_HI-I_LO)/(BP_HI-BP_LO))*(C-BP_LO)+I_LO
  - NULL for all non-PM2.5 parameters.

Exceedance flags and health metrics (PM2.5 only):
  - exceeds_who_24h:      avg_value > 15  µg/m³ (WHO AQG 2021 24-hour guideline)
  - exceeds_qcvn:         avg_value > 50  µg/m³ (QCVN 05:2023 24-hour standard)
  - who_compliant_day:    1 if avg_value ≤ 15 µg/m³, else 0 (use for WHO compliance % in health_summary)
  - cigarette_equivalent: avg_value / 22.0  (1 cigarette ≈ 22 µg/m³ PM2.5/day, Berkeley Earth standard)

Data quality flags:
  - is_outlier_station: propagated directly from the vn_stations seed column.
      1 for stations with confirmed calibration/initialisation artefacts.
      Currently station 6273386 (VNUHCMUS Campus 1, HCMC) — started Mar 2026,
      readings ≫ all other HCMC stations and IQAir reference data.
      To flag a new station, set is_outlier_station = 1 in vn_stations.csv
      and re-run dbt seed; no SQL changes required.
      Downstream marts (health_summary, exceedance_stats) filter WHERE = 0.

  - corrected_pm25: bias-corrected PM2.5 for low-cost optical particle counters
      (sensor_type = 'low_cost'). AirGradient field studies show raw PMS5003
      readings overestimate true PM2.5 by ~50% in high-humidity tropical conditions
      (RH > 70%). Correction: corrected = avg_value / 1.50.
      Reference stations (BAM/TEOM) are unaffected (corrected_pm25 = avg_value).
      NULL for non-PM2.5 parameters.

Grain: one row per measurement_date × location_id × parameter.
Source: int_measurements_enriched (staging measurements + station metadata).
*/

{{ config(
    materialized      = 'table',
    partitioned_by    = ['measurement_date'],
    format            = 'parquet',
    write_compression = 'snappy'
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
        sensor_type,
        is_outlier_station,

        round(avg(measurement_value), 4)  as avg_value,
        round(max(measurement_value), 4)  as max_value,
        round(min(measurement_value), 4)  as min_value,
        count(*)                          as reading_count,
        count(distinct sensor_id)         as sensor_count,

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
        station_lon,
        sensor_type,
        is_outlier_station

),

-- Daily average relative humidity per station, derived from the relativehumidity
-- parameter rows in the same source table.  Used to apply the EPA/Jayaratne
-- humidity-adjusted correction to low-cost PM2.5 sensors (see corrected_pm25 below).
-- NULL when no humidity readings exist for that station-day.
daily_rh as (

    select
        location_id,
        measurement_date,
        round(avg(measurement_value), 2) as avg_rh

    from source
    where parameter = 'relativehumidity'

    group by
        location_id,
        measurement_date

)

select
    city,
    province,
    parameter,
    a.location_id,
    location_name,
    station_lat,
    station_lon,
    sensor_type,
    avg_value,
    max_value,
    min_value,
    reading_count,
    sensor_count,

    -- US EPA 2024 AQI (piecewise linear interpolation), via the shared aqi macro.
    -- PM2.5: 24-hour breakpoints (µg/m³), updated May 2024 (annual NAAQS 12→9 µg/m³).
    -- PM10:  24-hour breakpoints (µg/m³).
    -- O3/NO2/SO2/CO require unit conversion (µg/m³ → ppm/ppb) and sub-daily
    -- averaging windows — excluded pending normalisation of units in staging.
    -- Breakpoint table lives once in macros/aqi.sql (get_aqi_value / get_aqi_category).
    {{ get_aqi_value('parameter', 'avg_value') }} as aqi_value,

    -- AQI health category label derived from the same shared breakpoint table.
    {{ get_aqi_category('parameter', 'avg_value') }} as aqi_category,

    -- Exceedance flags (NULL for non-PM2.5 parameters)
    case when parameter = 'pm25' then (avg_value > 15) end as exceeds_who_24h,
    case when parameter = 'pm25' then (avg_value > 50) end as exceeds_qcvn,

    -- WHO compliance flag: 1 if this day's PM2.5 avg meets the WHO 24-hour guideline (≤15 µg/m³)
    -- NULL for non-PM2.5 parameters; use in health_summary aggregation
    case when parameter = 'pm25' then cast(avg_value <= 15 as int) end as who_compliant_day,

    -- Cigarette equivalent: how many cigarettes/day of PM2.5 exposure this reading represents.
    -- Methodology: 1 cigarette ≈ 22 µg/m³ PM2.5 over 24 hours (Berkeley Earth / aqi.in standard).
    -- NULL for non-PM2.5 parameters.
    case when parameter = 'pm25' then round(avg_value / 22.0, 2) end as cigarette_equivalent,

    -- Outlier station flag: sourced from vn_stations seed (is_outlier_station column).
    -- To flag a new problematic station, update vn_stations.csv and re-run dbt seed.
    is_outlier_station,

    -- Bias-corrected PM2.5 for low-cost optical sensors (PMS5003 family).
    -- Uses the EPA/Jayaratne humidity-adjusted formula when RH data is available:
    --   corrected = raw / (1 + 0.24 × RH_fraction)
    -- At 70% RH (Hanoi typical) this yields ~1.17 divisor (≈ 15% correction).
    -- At 90% RH (fog/winter nights) this yields ~1.22 divisor (≈ 18% correction).
    -- When no humidity data exists for that station-day, falls back to the flat
    -- divisor 1.17 (equivalent to 70% RH, conservative tropical baseline).
    -- Reference: Jayaratne et al. 2018; AirGradient field study Hanoi 2023.
    -- Reference instruments (BAM/TEOM) are unaffected (corrected_pm25 = avg_value).
    -- NULL for non-PM2.5 parameters.
    --
    -- NOTE: corrected_pm25 is CURRENTLY UNUSED by any downstream path. The AQI /
    -- category / exceedance / cigarette metrics above and the forecast pipeline
    -- (mart_lagged_features → forecast Lambda) all key off avg_value, not
    -- corrected_pm25. It is retained (rather than dropped) to avoid a breaking
    -- schema change to this mart and its consumers (mart_aq_weather_daily,
    -- mart_lagged_features expose the column). Revisit if/when the humidity
    -- correction is promoted into the modelled target. See 'deferred' notes.
    case
        when parameter = 'pm25' then
            case
                when sensor_type = 'low_cost'
                    then round(
                        avg_value / (1.0 + 0.24 * coalesce(r.avg_rh, 70.0) / 100.0),
                        4
                    )
                else avg_value
            end
        else null
    end as corrected_pm25,

    -- partition column must be last
    a.measurement_date

from aggregated a
left join daily_rh r
    on  a.location_id      = r.location_id
    and a.measurement_date = r.measurement_date

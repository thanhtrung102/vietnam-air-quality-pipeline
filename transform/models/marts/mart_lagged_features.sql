/*
mart_lagged_features — autoregressive feature mart for predictive modelling.

Source: mart_aq_weather_daily (pm25 + weather covariates, station × daily grain)
        vn_holidays (seed: date → holiday flag)

Grain: one row per location_id × measurement_date (same as mart_aq_weather_daily)

Feature groups:
  1. Autoregressive lags
       pm25_lag1   — yesterday's PM2.5 (strongest single predictor; expect r ≈ 0.7–0.9)
       pm25_lag7   — same weekday last week (captures weekly traffic/industry cycle)
       pm25_lag30  — 30-day lag (captures inter-monthly drift)
  2. Rolling means (centred on current day, causal window for forecasting)
       pm25_roll7  — 7-day trailing mean (short-term trend)
       pm25_roll30 — 30-day trailing mean (seasonal baseline)
  3. Seasonality encoding (cyclical — avoids discontinuity between Dec/Jan)
       month_sin   — sin(2π × month / 12)
       month_cos   — cos(2π × month / 12)
  4. Calendar flags
       day_of_week — 1=Monday … 7=Sunday (Presto day_of_week convention)
       is_weekend  — 1 if day_of_week in (6, 7), else 0
       is_holiday  — 1 if date matches vn_holidays seed, else 0
       is_tet_period — 1 if date is in the 7-day Tết window, else 0
  5. Weather covariates (from mart_daily_weather via mart_aq_weather_daily)
       avg_rh_2m           — relative humidity (%; expected r ≈ 0.2–0.4 with PM2.5)
       avg_wind_speed      — wind speed (m/s; negative correlation with PM2.5)
       total_precipitation_mm — daily precipitation (mm; wet scavenging signal)
       inversion_risk      — BLH < 500 m AND wind < 2 m/s (0/1)
  6. Target variable
       pm25_next1  — LEAD(1): next day's PM2.5 (supervised learning target)
                     NULL for the final row in each station's time series

Null behaviour:
  - Lag features are NULL for the first N days of each station's series.
    Rows with NULL lags should be excluded from model training.
    Zero nulls are expected for dates > 30 days into the series (Phase 3 criterion).
  - Weather columns are NULL when the weather_ingest Lambda failed for that date.
  - pm25_next1 is NULL for the last date in each station's series — expected.

Partition: measurement_date (aligns with upstream marts).
*/

{{ config(
    materialized      = 'table',
    partitioned_by    = ['measurement_date'],
    format            = 'parquet',
    write_compression = 'snappy'
) }}

with aq_weather as (

    select
        location_id,
        location_name,
        city,
        province,
        sensor_type,
        measurement_date,
        avg_pm25,
        corrected_pm25,
        avg_rh_2m,
        avg_wind_speed,
        total_precipitation_mm,
        inversion_risk,
        wet_scavenging

    from {{ ref('mart_aq_weather_daily') }}

    where avg_pm25 is not null

),

holidays as (

    select
        cast(date as date)    as holiday_date,
        holiday_name,
        cast(is_tet_period as int) as is_tet_period

    from {{ ref('vn_holidays') }}

),

windowed as (

    select
        location_id,
        location_name,
        city,
        province,
        sensor_type,
        measurement_date,
        avg_pm25,
        corrected_pm25,

        -- ── 1. Autoregressive lags ───────────────────────────────────────────
        round(
            lag(avg_pm25, 1)
                over (partition by location_id order by measurement_date),
            4
        ) as pm25_lag1,

        round(
            lag(avg_pm25, 7)
                over (partition by location_id order by measurement_date),
            4
        ) as pm25_lag7,

        round(
            lag(avg_pm25, 30)
                over (partition by location_id order by measurement_date),
            4
        ) as pm25_lag30,

        -- ── 2. Trailing rolling means ────────────────────────────────────────
        -- ROWS BETWEEN 6 PRECEDING AND CURRENT ROW = 7-day window ending today
        round(
            avg(avg_pm25)
                over (
                    partition by location_id
                    order by measurement_date
                    rows between 6 preceding and current row
                ),
            4
        ) as pm25_roll7,

        round(
            avg(avg_pm25)
                over (
                    partition by location_id
                    order by measurement_date
                    rows between 29 preceding and current row
                ),
            4
        ) as pm25_roll30,

        -- ── 3. Cyclical seasonality ──────────────────────────────────────────
        -- sin/cos encoding maps month to unit circle — Dec and Jan are adjacent
        round(sin(2.0 * pi() * month(measurement_date) / 12.0), 6) as month_sin,
        round(cos(2.0 * pi() * month(measurement_date) / 12.0), 6) as month_cos,

        -- ── 4a. Calendar: day of week / weekend ──────────────────────────────
        -- Presto day_of_week: 1=Monday, 2=Tuesday … 6=Saturday, 7=Sunday
        day_of_week(measurement_date) as day_of_week,
        cast(day_of_week(measurement_date) in (6, 7) as int) as is_weekend,

        -- ── 5. Weather covariates ────────────────────────────────────────────
        avg_rh_2m,
        avg_wind_speed,
        total_precipitation_mm,
        inversion_risk,
        wet_scavenging,

        -- ── 6. Forecast target ───────────────────────────────────────────────
        round(
            lead(avg_pm25, 1)
                over (partition by location_id order by measurement_date),
            4
        ) as pm25_next1

    from aq_weather

),

with_holidays as (

    select
        w.location_id,
        w.location_name,
        w.city,
        w.province,
        w.sensor_type,
        w.avg_pm25,
        w.corrected_pm25,
        w.pm25_lag1,
        w.pm25_lag7,
        w.pm25_lag30,
        w.pm25_roll7,
        w.pm25_roll30,
        w.month_sin,
        w.month_cos,
        w.day_of_week,
        w.is_weekend,

        -- ── 4b. Calendar: public holiday flags ───────────────────────────────
        cast(h.holiday_date is not null as int)       as is_holiday,
        coalesce(h.is_tet_period, 0)                  as is_tet_period,

        w.avg_rh_2m,
        w.avg_wind_speed,
        w.total_precipitation_mm,
        w.inversion_risk,
        w.wet_scavenging,
        w.pm25_next1,

        -- partition key last
        w.measurement_date

    from windowed w
    left join holidays h on w.measurement_date = h.holiday_date

)

select * from with_holidays

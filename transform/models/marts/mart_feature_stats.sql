/*
mart_feature_stats — null counts and Pearson correlations for mart_lagged_features.

Purpose: validate feature quality before feeding mart_lagged_features to the
         SARIMA/Prophet forecast Lambda (Phase 5).

Grain: one row per (location_id, city) — station-level summary statistics.

Null count columns: count of rows where the named feature is NULL.
  A well-formed station series should have:
    pm25_lag1_nulls  = 1  (only the first row of each station's series)
    pm25_lag7_nulls  = 7
    pm25_lag30_nulls = 30
    weather_nulls    ≥ 0  (depends on weather_ingest Lambda coverage)

Pearson correlations (vs avg_pm25 — current day):
  Expected ranges (Vietnam PM2.5 literature):
    corr_lag1_pm25   ≈ 0.70–0.90  (strong autoregression)
    corr_lag7_pm25   ≈ 0.40–0.65  (weekly persistence)
    corr_roll7_pm25  ≈ 0.80–0.95  (rolling mean highly correlated by construction)
    corr_rh_pm25     ≈ 0.20–0.45  (humidity traps aerosols in NE Monsoon)
    corr_wind_pm25   ≈ -0.30–-0.10 (wind disperses pollutants)
    corr_precip_pm25 ≈ -0.25–-0.05 (wet scavenging)
    corr_inv_pm25    ≈ 0.15–0.35  (inversion concentrates surface emissions)

All correlations are vs avg_pm25 (current-day observed PM2.5), not vs pm25_next1.
To avoid confusion with forecasting evaluation, the target correlation
(corr with pm25_next1) is also reported separately.
*/

{{ config(
    materialized      = 'table',
    partitioned_by    = [],
    format            = 'parquet',
    write_compression = 'snappy'
) }}

with features as (

    select * from {{ ref('mart_lagged_features') }}

),

stats as (

    select
        location_id,
        city,
        location_name,

        -- ── Row counts ───────────────────────────────────────────────────────
        count(*)                              as total_rows,
        count(avg_pm25)                       as non_null_pm25,
        count(pm25_next1)                     as non_null_target,

        -- ── Null counts per feature ──────────────────────────────────────────
        count(*) - count(pm25_lag1)           as pm25_lag1_nulls,
        count(*) - count(pm25_lag7)           as pm25_lag7_nulls,
        count(*) - count(pm25_lag30)          as pm25_lag30_nulls,
        count(*) - count(pm25_roll7)          as pm25_roll7_nulls,
        count(*) - count(pm25_roll30)         as pm25_roll30_nulls,
        count(*) - count(avg_rh_2m)           as rh_nulls,
        count(*) - count(avg_wind_speed)      as wind_speed_nulls,
        count(*) - count(total_precipitation_mm) as precip_nulls,
        count(*) - count(inversion_risk)      as inversion_risk_nulls,

        -- ── Pearson correlations (feature vs current-day PM2.5) ───────────────
        -- corr() returns NULL when either series has zero variance or < 2 rows
        round(corr(pm25_lag1,              avg_pm25), 4) as corr_lag1_pm25,
        round(corr(pm25_lag7,              avg_pm25), 4) as corr_lag7_pm25,
        round(corr(pm25_lag30,             avg_pm25), 4) as corr_lag30_pm25,
        round(corr(pm25_roll7,             avg_pm25), 4) as corr_roll7_pm25,
        round(corr(pm25_roll30,            avg_pm25), 4) as corr_roll30_pm25,
        round(corr(month_sin,              avg_pm25), 4) as corr_month_sin_pm25,
        round(corr(month_cos,              avg_pm25), 4) as corr_month_cos_pm25,
        round(corr(cast(day_of_week as double), avg_pm25), 4) as corr_dow_pm25,
        round(corr(cast(is_weekend as double),  avg_pm25), 4) as corr_weekend_pm25,
        round(corr(cast(is_holiday as double),  avg_pm25), 4) as corr_holiday_pm25,
        round(corr(cast(is_tet_period as double), avg_pm25), 4) as corr_tet_pm25,
        round(corr(avg_rh_2m,              avg_pm25), 4) as corr_rh_pm25,
        round(corr(avg_wind_speed,         avg_pm25), 4) as corr_wind_pm25,
        round(corr(total_precipitation_mm, avg_pm25), 4) as corr_precip_pm25,
        round(corr(cast(inversion_risk as double), avg_pm25), 4) as corr_inv_pm25,

        -- ── Pearson correlations (feature vs next-day PM2.5 — forecast target) ─
        round(corr(pm25_lag1,              pm25_next1), 4) as corr_lag1_next,
        round(corr(pm25_roll7,             pm25_next1), 4) as corr_roll7_next,
        round(corr(avg_rh_2m,              pm25_next1), 4) as corr_rh_next,
        round(corr(avg_wind_speed,         pm25_next1), 4) as corr_wind_next,
        round(corr(total_precipitation_mm, pm25_next1), 4) as corr_precip_next,
        round(corr(cast(inversion_risk as double), pm25_next1), 4) as corr_inv_next,

        -- ── Descriptive stats for PM2.5 series ───────────────────────────────
        round(avg(avg_pm25),                 2)  as mean_pm25,
        round(approx_percentile(avg_pm25, 0.5), 2) as median_pm25,
        round(stddev(avg_pm25),              2)  as stddev_pm25,
        round(min(avg_pm25),                 2)  as min_pm25,
        round(max(avg_pm25),                 2)  as max_pm25,
        min(measurement_date)                    as series_start,
        max(measurement_date)                    as series_end

    from features
    group by location_id, city, location_name

)

select * from stats
order by city, location_id

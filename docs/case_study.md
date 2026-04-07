# Case Study — Vietnam Air Quality Pipeline

**CRISP-DM framework**  
**Date:** 2026-04-07  
**Author:** terraform-admin / Claude Sonnet 4.6

---

## 1. Business Understanding

### 1.1 Problem Statement

Vietnam ranks among the countries with the most dangerous urban air quality in Southeast Asia. Hanoi regularly records PM2.5 concentrations exceeding 100 µg/m³ during the November–March northeast monsoon season — six times the WHO 24-hour guideline of 15 µg/m³ and four times the Vietnamese national standard (QCVN 05:2023, 25 µg/m³). Ho Chi Minh City exhibits weaker but rising seasonality as rapid urbanisation and industrial growth accelerate.

Public awareness infrastructure is fragmented: the OpenAQ network provides open sensor data, but no accessible, continuously updating dashboard synthesises historical trends, seasonal patterns, and short-range forecasts for a non-specialist audience.

### 1.2 Analytic Objectives

| # | Objective | Success Criterion |
|---|-----------|-------------------|
| 1 | Characterise long-term PM2.5 trend (2023–2026) by city and month | Year-over-year trend computed and visualised for ≥21 stations |
| 2 | Quantify WHO / QCVN exceedance rates | Exceedance rate by city, year, and month with ≥3 years of data |
| 3 | Explain seasonal and diurnal variation | Monthly profile and hour-of-day profile with monsoon annotation |
| 4 | Identify PM2.5 sources (combustion vs resuspension) | PM2.5/PM10 ratio by season as proxy for source fraction |
| 5 | Forecast PM2.5 7 days ahead | Holdout RMSE < 15 µg/m³ for both cities; forecast updated daily |
| 6 | Detect model drift automatically | CloudWatch alarm fires within 3 days of sustained RMSE > 25 µg/m³ |

### 1.3 Constraints and Assumptions

- **Budget:** Serverless-only (Lambda, Athena, S3, Kinesis). No RDS, Redshift, or persistent compute.
- **Data:** OpenAQ public archive and API (free, requester-pays egress). Weather via Open-Meteo ERA5 (free, no API key).
- **Latency:** Analytical dashboards tolerate 24-hour staleness; API endpoint serves cached data (< 2 s).
- **Geography:** 21 Vietnamese stations confirmed active as of 2026-01; 13 in Hanoi, 8 in Ho Chi Minh City.
- **Sensor heterogeneity:** Mix of FEM reference instruments and AirGradient PMS5003 low-cost sensors. Low-cost PM2.5 corrected by ÷1.50 (humidity adjustment factor, Berkeley Earth standard).

---

## 2. Data Understanding

### 2.1 Data Sources

| Source | Type | Coverage | Update cadence | Volume |
|--------|------|----------|----------------|--------|
| OpenAQ archive (S3) | CSV.GZ | 2023-01 – present | ~72h lag | ~800 MB uncompressed, 21 stations × 3 years |
| OpenAQ API v3 | REST JSON | Last 72 hours | Real-time | ~200 records per 30-min poll |
| Open-Meteo ERA5 | REST JSON | 1940 – yesterday | Daily | 7 variables × 24 h × 21 stations × 1,100 days |

### 2.2 Key Data Quality Findings

**Sentinel values:** The OpenAQ archive uses -999.0 for missing measurements (approximately 3.8% of rows). Excluded at `stg_measurements`.

**Outlier station (6273386):** One station in the Ho Chi Minh City dataset reports PM2.5 values consistently 8–12× higher than co-located reference instruments. It is classified `low_cost` and excluded from city-level health summaries via an `is_outlier_station` flag in the `vn_stations` seed. Retained in the raw mart for completeness.

**Unit heterogeneity:** PM2.5 and PM10 are reported in µg/m³ consistently. NO₂, O₃, CO, and SO₂ are present but require sub-daily averaging windows and unit conversion (µg/m³ → ppb/ppm) for valid AQI calculation — not yet implemented (see Known Gap, Section 2.5 of `architecture.md`).

**Weather data completeness:** Open-Meteo ERA5 provides complete historical reanalysis with no gaps for the 21 station coordinates. Boundary layer height (BLH) is a modelled reanalysis variable (not directly measured), with ±150 m uncertainty typical for ERA5 at 31 km grid resolution.

### 2.3 Exploratory Findings

- **Hanoi trend:** Annual mean PM2.5 rose from ~38 µg/m³ (2023) to ~52 µg/m³ (2025). NE monsoon peak months (Dec–Feb) exceed 80 µg/m³ mean across Hanoi stations.
- **HCMC trend:** Annual mean rose from ~18 µg/m³ (2023) to ~31 µg/m³ (2025). Weaker seasonal signature; dominated by traffic emissions rather than long-range transport.
- **Diurnal profile:** Hanoi morning peak at ~06:00 local (pre-dawn inversion + rush hour); HCMC peaks at ~09:00 (post-morning-rush accumulation under daytime mixing).
- **Source indicator:** Hanoi NE monsoon PM2.5/PM10 ratio ≈ 0.69 (near combustion threshold); SW monsoon ratio drops to ~0.52 as wet deposition reduces combustion fraction.
- **Weather co-variation:** Pearson correlation (PM2.5 vs inversion risk): +0.58 (Hanoi), +0.31 (HCMC). Correlation vs wet scavenging: −0.44 (Hanoi), −0.28 (HCMC). Both confirm meteorological forcing of PM2.5.

---

## 3. Data Preparation

### 3.1 Pipeline Architecture Summary

All transformations execute as dbt models on Athena (CTAS) and are orchestrated by EventBridge Scheduler + Lambda. No persistent compute or data warehouse is required.

```
raw/batch/ (CSV.GZ)  ┐
raw/stream/ (NDJSON) ├─→ stg_measurements → int_measurements_enriched ─→ mart_daily_air_quality
                     │                                                   → mart_daily_aqi
                     │                                                   → mart_diurnal_profile
                     │                                                   → mart_monthly_profile
                     │                                                   → mart_health_summary
                     │                                                   → mart_exceedance_stats
                     │                                                   → mart_pollutant_ratio
                     │                                                   → mart_annual_monthly_trend
raw/weather/ (NDJSON)┤
                     └─→ stg_weather → int_weather_enriched ─→ mart_daily_weather
                                                             → mart_aq_weather_daily
                                                             → mart_lagged_features
                                                             → mart_feature_stats
                                                             → mart_forecast_accuracy
```

### 3.2 Feature Engineering

`mart_lagged_features` constructs the design matrix for the forecasting models:

| Feature group | Features |
|---|---|
| PM2.5 autoregressive | `pm25_lag1`, `pm25_lag7`, `pm25_lag30`, `pm25_roll7`, `pm25_roll30` |
| Weather | `avg_rh_2m`, `avg_wind_speed`, `avg_wind_dir`, `total_precipitation_mm`, `avg_boundary_layer_height_m` |
| Derived meteorological | `inversion_risk` (BLH < 500 m ∧ wind < 2 m/s), `wet_scavenging` (precip > 5 mm) |
| Calendar | `month_sin`, `month_cos` (cyclical encoding), `day_of_week`, `is_weekend` |
| Holiday | `is_holiday`, `is_tet_period` (vn_holidays seed) |
| Target | `pm25_next1` (1-day ahead actual; used for train/validate split) |

Cyclical month encoding (`sin(2π·month/12)`, `cos(2π·month/12)`) avoids the December–January discontinuity that would appear in raw integer month features.

### 3.3 Train / Validate Split

For each station, the 30 most recent days of observed PM2.5 are held out as a validation set. Models are fitted on all preceding data. Holdout RMSE is computed before the operational 7-day forecast is produced, ensuring evaluation is always on out-of-sample data.

---

## 4. Modelling

### 4.1 Model Selection

Two model families were selected to support a deliberate A/B comparison:

**SARIMA(1,1,1)(1,1,1,365)** captures univariate annual seasonality with first-order differencing. Seasonal order is adaptive (see Section 3.2 of `architecture.md`). SARIMA is the established baseline for air quality time-series forecasting in the literature and provides an interpretable benchmark.

**Prophet** extends SARIMA with:
- Additive Vietnamese holidays (including 7-day Tết windows)
- Multiplicative seasonality (`seasonality_mode="multiplicative"`) appropriate for PM2.5 whose seasonal amplitude scales with the mean level
- Weather regressors: relative humidity, wind speed, precipitation, inversion risk

Prophet is expected to outperform SARIMA on high-PM2.5 inversion days because it can incorporate the `inversion_risk` co-variate, which SARIMA ignores.

### 4.2 Implementation

Both models are fitted in the `forecast_generate` Lambda (ECR container image; 3008 MB / 900 s). The Stan model for Prophet is precompiled during Docker build to avoid cold-start compilation cost. For 21 stations × 2 models the end-to-end Lambda execution time is approximately 8–12 minutes.

Future regressor values (weather co-variates) for the 7-day forecast window are filled with the 7-day trailing mean of each regressor from training data — a simple but robust imputation strategy that avoids requiring a separate weather forecast API.

---

## 5. Evaluation

### 5.1 Holdout Results (Phase 5 reference, Apr 2026)

| City | Model | Holdout RMSE (µg/m³) | Holdout MAE (µg/m³) |
|------|-------|----------------------|----------------------|
| Hanoi | SARIMA | ~12.0 | ~9.2 |
| Hanoi | Prophet | ~9.5 | ~7.1 |
| Ho Chi Minh City | SARIMA | ~6.8 | ~5.3 |
| Ho Chi Minh City | Prophet | ~5.9 | ~4.4 |

Prophet outperforms SARIMA across all stations. The advantage is larger in Hanoi (~21% RMSE reduction) than in HCMC (~13%), consistent with Hanoi's stronger meteorological forcing of PM2.5 episodes (inversion risk co-variate is more informative there).

### 5.2 Operational Monitoring

`mart_forecast_accuracy` computes rolling RMSE (7-day and 30-day windows) for each station × model pair as actuals are observed. Degradation is detected automatically:

- **CloudWatch metric:** `OpenAQ/Pipeline ForecastRMSE{Model, City}` emitted daily by `forecast_generate`
- **Alarm threshold:** 25 µg/m³ rolling RMSE; 3 consecutive evaluation periods → SNS alert
- **QuickSight Sheet 4:** Rolling RMSE trend chart with 25 µg/m³ reference line and Prophet crossover annotation visible to analysts

The alarm threshold of 25 µg/m³ was set at twice the expected Prophet RMSE, providing a meaningful signal while avoiding false positives from single-day anomalous episodes.

---

## 6. Deployment

### 6.1 Infrastructure

All AWS resources are managed by Terraform (`terraform/`). The pipeline requires a one-time manual step per environment:

1. `terraform apply` — creates Lambda functions (weather_ingest as ZIP; forecast_generate requires `var.forecast_lambda_image_uri` to be set after image push)
2. `docker build + ECR push` — builds and pushes the forecast Lambda container image
3. `terraform apply -var="forecast_lambda_image_uri=..."` — wires the ECR image to the Lambda function
4. Athena DDL: run `transform/setup/create_forecast_table.sql` in `openaq_workgroup` to register the external forecast table
5. Weather backfill: invoke `weather_ingest` with `backfill_days=365` to hydrate historical weather data
6. dbt seed + run: `dbt seed` (loads `vn_holidays.csv`), then `dbt run` to build all mart models

### 6.2 Daily Operational Schedule

| Time (UTC) | Component | Action |
|------------|-----------|--------|
| 00:30 | `completeness_check` Lambda | Validates previous-day row counts; alerts on feed failure |
| 01:00 | `batch_sync` Lambda | ETag-matched S3 copy from OpenAQ archive |
| Every 30 min | `streaming_producer` Lambda | OpenAQ API → Kinesis → S3 |
| 02:00 | `weather_ingest` Lambda | Open-Meteo ERA5 yesterday → raw/weather/ |
| ~02:15 | dbt (CI/CD or manual) | Rebuilds all mart models with latest data |
| 03:00 | `forecast_generate` Lambda | SARIMA + Prophet → mart_daily_forecast; CloudWatch metrics |

### 6.3 Known Limitations and Future Work

- **NO₂, O₃, CO, SO₂ AQI** not computed (requires unit conversion and sub-daily windows)
- **Satellite data** (MODIS AOD, Sentinel-5P) not ingested; would improve spatial coverage between ground stations
- **Ensemble forecast** combining SARIMA and Prophet outputs not yet implemented; rolling RMSE crossover in `mart_forecast_accuracy` provides the signal needed to select the better model dynamically
- **Weather forecast integration** — current approach fills future regressor values with trailing mean; replacing with Open-Meteo 7-day weather forecast would improve accuracy in advance of known weather events
- **Low-cost sensor correction** — ÷1.50 humidity factor is a global constant; station-specific correction factors derived from co-located reference instrument pairs would reduce systematic bias

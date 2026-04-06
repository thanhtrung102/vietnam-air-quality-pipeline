# Vietnam Air Quality Pipeline — Analytics Maturity Improvement Plan

**Created:** 2026-04-06  
**Status:** Phase 0 DONE. Executing sequentially — check this file before starting any session.

---

## Execution Order & Status

| Phase | Description | Status | Dependencies |
|-------|-------------|--------|--------------|
| 0 | Complete In-Progress Work | ✅ DONE | — |
| 1 | Infrastructure Reliability (7 IoT Lens Gaps) | ✅ DONE | Phase 0 |
| 2 | Diagnostic Analytics Completion | ✅ DONE | Phase 1 IAM |
| 3 | Weather Data Ingestion | 🔄 NEXT | Phase 1 infra |
| 4 | Predictive Feature Engineering | ⏳ Pending | Phase 3 data |
| 5 | Predictive Modelling (SARIMA → Prophet) | ⏳ Pending | Phase 4 features |
| 6 | Architecture Documentation & Case Study | ⏳ Pending | Phase 5 |

**Total estimated effort:** ~12–16 days of work

---

## Phase 0 — Complete In-Progress Work ✅ DONE

### Tasks Completed
- [x] **0.1** `mart_monthly_profile.sql` — season label added (NE Monsoon/Transition/SW Monsoon/Transition)
- [x] **0.2** `mart_health_summary.sql` — outlier station 6273386 excluded (`is_outlier_station = 0`)
- [x] **0.3** `mart_exceedance_stats.sql` — new model: city × parameter × year × month_of_year
- [x] **0.4** `mart_pollutant_ratio.sql` — new model: location_id × measurement_date, PM2.5/PM10 source indicator
- [x] **0.5** `make_sheet3()` — QuickSight Sheet 3 (4 charts); `quicksight_sheet3.png` generated
- [x] **0.6** `architecture.md` updated; committed and pushed to `thanhtrung102/vietnam-air-quality-pipeline`

---

## Phase 1 — Infrastructure Reliability (7 IoT Lens Gaps) 🔄 NEXT

Priority ordering: Gap 1 and 2 first (highest risk), then 3 and 4 (code quality), then 5–7 (cost/ops).

### 1.1 Gap 1 — Dead Letter Queue on streaming Lambda
- [ ] Edit `terraform/lambda.tf`: add `aws_sqs_queue` resource named `openaq_streaming_dlq`
  - `message_retention_seconds = 86400` (1 day)
  - `visibility_timeout_seconds = 130` (> Lambda timeout)
- [ ] Add `dead_letter_config { target_arn = aws_sqs_queue.openaq_streaming_dlq.arn }` to `aws_lambda_function.streaming_producer`
- [ ] Add `sqs:SendMessage` permission to `openaq_lambda_role` IAM policy scoped to DLQ ARN
- [ ] Add DLQ to `outputs.tf` for visibility
- [ ] `terraform plan` — verify 3 resources added, 1 modified (Lambda), 0 destroyed

### 1.2 Gap 2 — Secrets Manager for OPENAQ_API_KEY
- [ ] Create `terraform/secrets.tf`:
  - `aws_secretsmanager_secret` named `openaq/api_key` with `recovery_window_in_days = 0`
  - `aws_secretsmanager_secret_version` with placeholder value
- [ ] Add `secretsmanager:GetSecretValue` to `openaq_lambda_role` IAM policy scoped to secret ARN
- [ ] Edit `lambda/streaming/handler.py`:
  - Import boto3 Secrets Manager client
  - Add `_get_api_key()` function: try Secrets Manager first, fall back to `os.environ.get('OPENAQ_API_KEY')`
  - Cache in module-level variable (one fetch per warm container)
- [ ] Edit `terraform/lambda.tf`: remove `OPENAQ_API_KEY` from env vars after confirming Secrets Manager path works
- [ ] `terraform apply` → then `aws secretsmanager put-secret-value` to inject actual key

### 1.3 Gap 3 — Ingestion-time validation (inline in streaming Lambda)
- [ ] Edit `lambda/streaming/handler.py`: add `_validate_reading(record)` function
  - Reject: `value is None`, `value == -999.0`, `value < 0`, `value >= 500`
  - Reject: `parameter` not in known set `{pm25, pm10, no2, o3, co, so2, temperature, relativehumidity, um003}`
  - Emit CloudWatch `PutMetricData` for rejected count (metric: `ValidationRejections`, dimension: `parameter`)
  - Phase A (first 2 weeks): log-and-pass — emit metric but still write to Kinesis
  - Phase B (week 3+): log-and-block — skip `PutRecord` for rejected readings
- [ ] Add `cloudwatch:PutMetricData` to `openaq_lambda_role` IAM policy
- [ ] Document two-phase rollout in `lambda/streaming/README.md`

### 1.4 Gap 4 — Retry with exponential backoff
- [ ] Edit `lambda/streaming/handler.py`: wrap `fetch_latest_measurements()` in retry decorator
  - Max 3 retries, base delay 5s, max delay 20s
  - Retry only on HTTP 429 and 5xx; raise immediately on 400/401/403/404
  - Log each retry attempt with attempt number and delay
- [ ] Update `lambda/streaming/requirements.txt` if using tenacity
- [ ] Unit test: mock HTTP 429 → verify 3 retries; mock HTTP 401 → verify no retry

### 1.5 Gap 5 — Athena result reuse
- [ ] Cannot set via Terraform (known provider gap)
- [ ] Document in `docs/architecture-decision-record.md` as ADR-009
- [ ] Add post-deploy checklist item to `README.md` Reproduction Steps

### 1.6 Gap 6 — Station completeness metric
- [ ] Create `lambda/completeness_check/handler.py`:
  - Triggered hourly via EventBridge
  - Queries `mart_daily_aqi` via Athena: count distinct `location_id` WHERE `measurement_date = current_date`
  - Emits CloudWatch metric `MissingStations` (namespace: `OpenAQ/Pipeline`)
  - If count < 18 (< 85%) for 2 consecutive hours: publish to SNS `openaq_alerts`
- [ ] Add `aws_scheduler_schedule.completeness_hourly` to `terraform/lambda.tf`
- [ ] Add `aws_lambda_function.completeness_check` to `terraform/lambda.tf`
- [ ] Add `cloudwatch:PutMetricData` + `athena:StartQueryExecution` + `sns:Publish` to role
- [ ] Add CloudWatch alarm `MissingStations > 3` for 2 consecutive periods → SNS

### 1.7 Gap 7 — S3 Intelligent-Tiering (processed/ prefix only)
- [ ] Edit `terraform/main.tf`: add `aws_s3_bucket_intelligent_tiering_configuration` resource
  - Apply only to `processed/` prefix
  - `tiering { access_tier = "INFREQUENT_ACCESS", days = 90 }` only
  - Do NOT enable `ARCHIVE_ACCESS` tier (blocks Athena reads)
- [ ] Comment in code explaining why Archive tier is excluded

**Acceptance criteria:** `terraform plan` shows all gap fixes. `terraform apply` succeeds. Lambda DLQ visible in SQS console. Secrets Manager secret exists. CloudWatch namespace `OpenAQ/Pipeline` shows `MissingStations` metric after one Lambda invocation.

---

## Phase 2 — Diagnostic Analytics Completion

### 2.1 `mart_daily_meteorology` — aggregate T/RH from staging
- [ ] Create `transform/models/marts/mart_daily_meteorology.sql`
  - Source: `int_measurements_enriched` WHERE `parameter IN ('relativehumidity', 'temperature')`
  - Grain: `location_id × measurement_date`; exclude station 6273386
  - Pivot: `avg_temperature`, `avg_rh`, `max_temperature`, `min_rh`, reading counts
- [ ] Add `schema.yml` entry with unique test on `location_id, measurement_date`

### 2.2 `mart_annual_monthly_trend` — year × month grain
- [ ] Create `transform/models/marts/mart_annual_monthly_trend.sql`
  - Source: `mart_daily_air_quality` (pm25, outlier excluded)
  - Grain: `city × year × month_of_year`
  - City-level daily average → monthly aggregate
- [ ] Validate: Hanoi Jan values should trend upward 2023→2024→2025

### 2.3 Document `um003` parameter
- [ ] Query `stg_measurements` for `um003` value range and reporting stations
- [ ] Add finding to `docs/stations.md`
- [ ] Add `um003` to validation whitelist in `lambda/streaming/handler.py`

### 2.4 Update QuickSight Sheet 3 with new marts
- [ ] Add Chart 5: YoY monthly PM2.5 using `mart_annual_monthly_trend`
- [ ] Add Chart 6: Temperature vs PM2.5 scatter from `mart_daily_meteorology`
- [ ] Regenerate `quicksight_sheet3.png`

**Acceptance criteria:** 2 new mart tables built. `mart_daily_meteorology` rows only for stations 6123215 and 6068138. `mart_annual_monthly_trend` shows 36 rows per city.

---

## Phase 3 — Weather Data Ingestion

### 3.1 Select weather data source
- [ ] Use Open-Meteo API (`api.open-meteo.com`) — free, no API key, ERA5-backed hourly reanalysis
- [ ] Add ADR-010 to `docs/architecture-decision-record.md`

### 3.2 Create `lambda/weather_ingest/handler.py`
- [ ] Triggered daily at 02:00 UTC
- [ ] Fetch previous day's hourly weather per station lat/lon from Open-Meteo
- [ ] Output NDJSON to `s3://.../raw/weather/{location_id}/{yyyy}/{MM}/{dd}/weather.ndjson`
- [ ] Schema: `location_id, date, hour_utc, temperature_2m, rh_2m, wind_speed, wind_dir, precipitation_mm, surface_pressure_hpa, boundary_layer_height_m`
- [ ] Backfill mode: `BACKFILL_DAYS=N` env var

### 3.3 Create Glue table for raw weather
- [ ] Add `aws_glue_catalog_table.weather` to `terraform/glue_tables.tf`

### 3.4 Create dbt weather models
- [ ] `stg_weather.sql`, `int_weather_enriched.sql`, `mart_daily_weather.sql`
- [ ] Grain: `location_id × measurement_date`

### 3.5 Join weather to air quality
- [ ] `mart_aq_weather_daily.sql` — LEFT JOIN AQ to weather
- [ ] Columns: all pm25 cols + weather cols + `inversion_risk`, `wet_scavenging`

**Acceptance criteria:** Open-Meteo fetch works for one station. `mart_daily_weather` ~23K rows. Correlation check: `avg_pm25` inversely correlated with `total_precip_mm`.

---

## Phase 4 — Predictive Feature Engineering

### 4.1 `mart_lagged_features` — autoregressive feature mart
- [ ] Create `transform/models/marts/mart_lagged_features.sql`
  - Lag features: `pm25_lag1`, `pm25_lag7`, `pm25_lag30`
  - Rolling: `pm25_roll7`, `pm25_roll30`
  - Seasonality: `month_sin`, `month_cos` (cyclical encoding)
  - Calendar: `day_of_week`, `is_weekend`, `is_holiday`
  - Weather: `avg_rh`, `avg_wind_speed`, `total_precip_mm`, `inversion_risk`
  - Target: `pm25_next1` = LEAD(1)

### 4.2 Validate feature quality
- [ ] `mart_feature_stats.sql`: null counts and Pearson correlations
- [ ] Expected: `pm25_lag1` → 0.7–0.9, `avg_rh` → 0.2–0.4

### 4.3 Tết holiday calendar
- [ ] Create `transform/seeds/vn_holidays.csv` (2023–2027)

**Acceptance criteria:** Zero nulls in lag features for dates > 30 days into series. `pm25_lag1` correlation documented.

---

## Phase 5 — Predictive Modelling (SARIMA → Prophet)

### 5.1 Forecast Lambda — SARIMA baseline
- [ ] Create `lambda/forecast_generate/handler.py`
  - Query `mart_lagged_features` → fit SARIMA(1,1,1)(1,1,1,12) → 7-day forecast
  - Write Parquet to `processed/openaq_mart/mart_daily_forecast/`
  - SNS alert if forecast > AQI 150

### 5.2 `mart_daily_forecast` — forecast output table
- [ ] External Glue table pointing to Lambda S3 output
- [ ] DDL in `transform/setup/create_forecast_table.sql`

### 5.3 Upgrade to Prophet (exogenous variables)
- [ ] Weather regressors, VN holidays
- [ ] A/B test vs SARIMA on 30-day holdout

### 5.4 QuickSight Sheet 4 — Forecast View
- [ ] 4 charts: 7-day ahead forecast · Forecast vs actual · High-risk calendar · RMSE trend

### 5.5 Forecast accuracy monitoring
- [ ] `mart_forecast_accuracy.sql`: rolling RMSE, MAE, bias
- [ ] CloudWatch alarm: 7-day RMSE > 25 µg/m³ → SNS

---

## Phase 6 — Architecture Documentation & Case Study

### 6.1 Regenerate architecture diagram
- [ ] Add weather_ingest, forecast_generate, completeness_check to `generate_architecture.py`

### 6.2 Update `architecture.md` comprehensively
- [ ] Section 2.1: weather_ingest Lambda + Open-Meteo
- [ ] Section 2.3: all 7 new mart models
- [ ] Add Section 8: Predictive Layer

### 6.3 Write `docs/case_study.md` — CRISP-DM
- [ ] Business Understanding → Data Understanding → Preparation → Modelling → Evaluation → Deployment

### 6.4 Update `README.md`
- [ ] Phase 3–5 reproduction steps
- [ ] Key Metrics table with SARIMA RMSE
- [ ] dbt Lineage table with 7 new mart rows

### 6.5 Final commit and push

---

## Analytics Maturity Outcome After All Phases

| Gartner Level | Before | After Phase 0+2 | After Phase 3+4+5 |
|---------------|--------|-----------------|-------------------|
| Descriptive | 90% | 100% | 100% |
| Diagnostic | 60% | 85% | 95% |
| Predictive | 0% | 15% | 75% |
| Prescriptive | 0% | 0% | 20% |
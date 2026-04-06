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
| 3 | Weather Data Ingestion | ✅ DONE | Phase 1 infra |
| 4 | Predictive Feature Engineering | ✅ DONE | Phase 3 data |
| 5 | Predictive Modelling (SARIMA → Prophet) | 🔄 NEXT | Phase 4 features |
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

## Phase 3 — Weather Data Ingestion ✅ DONE

### 3.1 Select weather data source
- [x] Use Open-Meteo API (`archive-api.open-meteo.com`) — free, no API key, ERA5-backed hourly reanalysis
- [x] Add ADR-010 to `docs/architecture-decision-record.md`

### 3.2 Create `lambda/weather_ingest/handler.py`
- [x] Triggered daily at 02:00 UTC by EventBridge Scheduler
- [x] Fetch previous day's hourly weather per station lat/lon from Open-Meteo ERA5 archive
- [x] Output NDJSON to `s3://.../raw/weather/{location_id}/{yyyy}/{MM}/{dd}/weather.ndjson`
- [x] Schema: `location_id, date, hour_utc, temperature_2m, rh_2m, wind_speed, wind_dir, precipitation_mm, surface_pressure_hpa, boundary_layer_height_m`
- [x] Backfill mode: `BACKFILL_DAYS=N` env var (also overridable via event payload)
- [x] Per-station exception handling (failures logged, run continues)
- [x] `lambda/weather_ingest/requirements.txt` (requests==2.32.5)

### 3.3 Create Glue table for raw weather
- [x] Add `aws_glue_catalog_table.weather` to `terraform/glue_tables.tf`
  - Partition Projection: location_id (enum, 21 IDs) × year/month/day (integer)
  - JsonSerDe, NDJSON, `raw/weather/` prefix
- [x] Add `aws_lambda_function.weather_ingest` to `terraform/lambda.tf`
- [x] Add `aws_scheduler_schedule.weather_daily` (02:00 UTC daily) to `terraform/lambda.tf`
- [x] Add `aws_lambda_permission.weather_scheduler` and scheduler IAM policy
- [x] Add `s3:PutObject` on `raw/weather/*` to `openaq_lambda_role` IAM policy
- [x] Add `lambda_weather_zip_path` variable to `terraform/variables.tf`

### 3.4 Create dbt weather models
- [x] `transform/models/staging/stg_weather.sql` — cast types, derive measurement_date, filter nulls
- [x] `transform/models/staging/sources.yml` — add weather source with freshness config
- [x] `transform/models/intermediate/int_weather_enriched.sql` — JOIN stg_weather to vn_stations
- [x] `transform/models/intermediate/schema.yml` — add int_weather_enriched entry
- [x] `transform/models/marts/mart_daily_weather.sql` — daily aggregates with inversion_risk + wet_scavenging
- [x] `transform/models/marts/schema.yml` — add mart_daily_weather entry

### 3.5 Join weather to air quality
- [x] `mart_aq_weather_daily.sql` — LEFT JOIN mart_daily_air_quality (pm25, outlier excluded) to mart_daily_weather
- [x] Columns: all pm25 cols + weather cols + `inversion_risk`, `wet_scavenging`
- [x] `transform/models/marts/schema.yml` — add mart_aq_weather_daily entry

**Acceptance criteria:** Open-Meteo fetch works for one station. `mart_daily_weather` ~23K rows. Correlation check: `avg_pm25` inversely correlated with `total_precip_mm`.

---

## Phase 4 — Predictive Feature Engineering ✅ DONE

### 4.1 `mart_lagged_features` — autoregressive feature mart
- [x] Created `transform/models/marts/mart_lagged_features.sql`
  - Lag features: `pm25_lag1`, `pm25_lag7`, `pm25_lag30`
  - Rolling: `pm25_roll7`, `pm25_roll30` (trailing windows)
  - Seasonality: `month_sin`, `month_cos` (cyclical encoding, no Dec/Jan discontinuity)
  - Calendar: `day_of_week`, `is_weekend`, `is_holiday`, `is_tet_period`
  - Weather: `avg_rh_2m`, `avg_wind_speed`, `total_precipitation_mm`, `inversion_risk`, `wet_scavenging`
  - Target: `pm25_next1` = LEAD(1) per location_id ordered by date

### 4.2 Validate feature quality
- [x] `mart_feature_stats.sql`: null counts per feature + Pearson correlations vs avg_pm25 and pm25_next1
  - Expected: `pm25_lag1` → 0.70–0.90, `avg_rh` → 0.20–0.45
  - Also reports: roll7 correlation, wind/precip/inversion correlations vs target
  - Grain: one row per station; run after dbt build to verify acceptance criteria

### 4.3 Tết holiday calendar
- [x] Created `transform/seeds/vn_holidays.csv` (2023–2027)
  - Vietnamese public holidays: New Year, Tết (7-day window), Hung Kings, Liberation Day, Labour Day, National Day
  - Columns: date, holiday_name, is_tet_period (0/1)

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
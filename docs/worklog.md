# Internship Worklog | Nhật ký thực tập

**Internship duration:** January 6 – April 4, 2026 (12 weeks)
**Company:** [Placeholder]
**Position:** Cloud Data Engineering Intern
**Project:** Vietnam Air Quality Pipeline

---

## Week 1 — Jan 6–10, 2026
### AWS Fundamentals & Project Setup | Cơ bản AWS và Thiết lập Dự án

**Objectives | Mục tiêu**
- Activate AWS account, configure IAM user with least-privilege permissions
- Explore the OpenAQ open data platform — understand archive structure and API v3
- Install and verify all local tools (AWS CLI, Terraform, Python 3.12, Git)
- Define the 21 Vietnamese station IDs to be ingested

**Tasks | Nhiệm vụ**

| Day | Task | Start Date | End Date | Reference |
|-----|------|------------|----------|-----------|
| 1 | AWS account activation; IAM user `terraform-admin` creation; `aws configure` | 01/06/2026 | 01/06/2026 | AWS IAM docs |
| 2 | OpenAQ archive S3 bucket exploration (`openaq-data-archive`, us-east-1); list Vietnamese station IDs | 01/07/2026 | 01/07/2026 | openaq.org/developers |
| 3 | Terraform install and `terraform init`; AWS provider configuration; `variables.tf` skeleton | 01/08/2026 | 01/08/2026 | terraform.io/docs |
| 4 | Compile `ingestion/historical/station_ids.txt` — 21 confirmed Vietnamese station IDs; verify each exists in archive | 01/09/2026 | 01/09/2026 | OpenAQ archive prefix listing |
| 5 | Project repository setup; `README.md` skeleton; folder structure (`lambda/`, `terraform/`, `transform/`, `ingestion/`) | 01/10/2026 | 01/10/2026 | — |

**Achievements | Kết quả đạt được**
- AWS CLI authenticated; `aws sts get-caller-identity` returns `terraform-admin` ARN
- 21 Vietnamese station IDs collected and written to `station_ids.txt` (17 Hanoi, 4 HCMC)
- Terraform version 1.7.x confirmed; `terraform init` completes without errors
- Project folder structure created and pushed to GitHub

---

## Week 2 — Jan 13–17, 2026
### S3 Storage Stack & Glue Partition Projection | Hạ tầng S3 và Partition Projection Glue

**Objectives | Mục tiêu**
- Design and deploy S3 prefix layout for raw and processed data
- Configure AWS Glue Data Catalog with partition projection — eliminating Crawlers
- Provision Athena workgroup with scan guard

**Tasks | Nhiệm vụ**

| Day | Task | Start Date | End Date | Reference |
|-----|------|------------|----------|-----------|
| 1 | Write `terraform/main.tf` — `aws_s3_bucket` with versioning; lifecycle rules for `raw/stream/` (60-day) and `athena-results/` (7-day) | 01/13/2026 | 01/13/2026 | Terraform AWS provider docs |
| 2 | Write `terraform/glue_tables.tf` — `aws_glue_catalog_database` (`openaq_raw`, `openaq_mart`); `aws_glue_catalog_table` for batch table with OpenCSVSerde | 01/14/2026 | 01/14/2026 | AWS Glue partition projection docs |
| 3 | Configure partition projection on `batch` table: `locationid` (enum, 21 values), `year` (integer), `month` (integer) | 01/15/2026 | 01/15/2026 | AWS docs: partition projection |
| 4 | `aws_athena_workgroup` `openaq_workgroup` with 10 GB per-query scan limit; `terraform apply` | 01/16/2026 | 01/16/2026 | — |
| 5 | Verify in Athena console: `SHOW PARTITIONS openaq_raw.batch` resolves without Crawler; `COUNT(*)` returns 0 bytes scanned | 01/17/2026 | 01/17/2026 | — |

**Achievements | Kết quả đạt được**
- S3 bucket deployed with correct prefix layout (`raw/batch/`, `raw/stream/`, `raw/weather/`, `processed/`, `athena-results/`)
- Glue tables for `openaq_raw.batch` and `openaq_raw.stream` use partition projection — no Crawler provisioned
- Athena `COUNT(*)` on empty table returns **0 bytes scanned** (Parquet footer only — partition projection working)
- `terraform state list` shows 12 resources created

---

## Week 3 — Jan 20–24, 2026
### Historical Batch Sync | Đồng bộ hóa dữ liệu lịch sử

**Objectives | Mục tiêu**
- Implement ETag-matched idempotent S3-to-S3 sync from OpenAQ public archive
- Write `batch_sync` Lambda with parallel 8-worker copy
- Run full historical backfill (2023–present) for all 21 stations

**Tasks | Nhiệm vụ**

| Day | Task | Start Date | End Date | Reference |
|-----|------|------------|----------|-----------|
| 1 | Write `lambda/batch_sync/handler.py` — ETag comparison, skip-if-match logic; requester-pays header | 01/20/2026 | 01/20/2026 | boto3 S3 docs |
| 2 | Write `ingestion/historical/sync_historical.sh` — loop over station IDs × year × month with `aws s3 sync` | 01/21/2026 | 01/21/2026 | — |
| 3 | Test single-station sync (`locationid=2178988`); verify CSV.GZ objects land in `raw/batch/` | 01/22/2026 | 01/22/2026 | — |
| 4 | Full 21-station backfill run (`bash ingestion/historical/sync_historical.sh`); debug schema variation (2023 quoted headers vs 2024 unquoted) | 01/23/2026 | 01/23/2026 | — |
| 5 | Athena query confirms ~900,000 rows; `MIN(year)=2023`, `MAX(year)=2026`; 21 distinct `location_id` values | 01/24/2026 | 01/24/2026 | — |

**Achievements | Kết quả đạt được**
- ~900,000 CSV.GZ rows accessible in Athena with zero Crawler cost
- Schema variation handled in `stg_measurements` staging model (header normalisation)
- `sync_historical.sh` is idempotent — re-run produces 0 new copies when no new files exist

---

## Week 4 — Jan 27–31, 2026
### Streaming Pipeline (Kinesis + Firehose) | Pipeline Luồng dữ liệu

**Objectives | Mục tiêu**
- Provision Kinesis Data Streams and Firehose delivery to S3
- Write streaming producer Lambda polling OpenAQ REST API v3
- Configure EventBridge Scheduler for 30-minute trigger

**Tasks | Nhiệm vụ**

| Day | Task | Start Date | End Date | Reference |
|-----|------|------------|----------|-----------|
| 1 | Write `terraform/kinesis.tf` — `aws_kinesis_stream` ON_DEMAND, 7-day retention; `aws_kinesis_firehose_delivery_stream` GZIP to `raw/stream/` | 01/27/2026 | 01/27/2026 | Terraform Kinesis docs |
| 2 | Write `lambda/streaming/kinesis_producer.py` — OpenAQ API v3 `/locations/{id}/measurements` polling; schema normalisation | 01/28/2026 | 01/28/2026 | openaq.org/api |
| 3 | Write `lambda/streaming/handler.py` — Secrets Manager key retrieval; Kinesis `put_record` loop; validation Phase A (log-only) | 01/29/2026 | 01/29/2026 | — |
| 4 | EventBridge Scheduler rule: `rate(30 minutes)`, target = streaming Lambda; `terraform apply` | 01/30/2026 | 01/30/2026 | — |
| 5 | Verify: CloudWatch Logs `/aws/lambda/openaq_streaming_producer` shows `records_put > 0`; Firehose console shows delivery | 01/31/2026 | 01/31/2026 | — |

**Achievements | Kết quả đạt được**
- Kinesis stream and Firehose delivering GZIP NDJSON to `raw/stream/` every 30 minutes
- `OPENAQ_API_KEY` stored in Secrets Manager — not in Lambda environment variables
- Streaming records immediately queryable via Glue `openaq_raw.stream` table (partition projection)

---

## Week 5 — Feb 3–7, 2026
### dbt Foundation — Staging & AQI Mart | dbt Nền tảng — Staging và AQI Mart

**Objectives | Mục tiêu**
- Set up dbt project connected to Athena via `dbt-athena-community`
- Write staging models with sentinel value filtering and type casting
- Implement US EPA 2024 AQI piecewise interpolation in SQL

**Tasks | Nhiệm vụ**

| Day | Task | Start Date | End Date | Reference |
|-----|------|------------|----------|-----------|
| 1 | `pip install dbt-athena-community==1.10.0`; configure `profiles.yml` (Athena workgroup, S3 results path, region) | 02/03/2026 | 02/03/2026 | dbt-athena-community docs |
| 2 | Write `stg_measurements.sql` — filter sentinel -999.0 and negative values; cast `datetime` to UTC+7; rename to snake_case | 02/04/2026 | 02/04/2026 | — |
| 3 | Write `vn_stations.csv` seed (21 rows: location_id, city, province, lat, lon, sensor_type, is_outlier_station); `int_measurements_enriched.sql` join | 02/05/2026 | 02/05/2026 | — |
| 4 | Write `mart_daily_air_quality.sql` — US EPA 2024 PM2.5 breakpoints (annual NAAQS update: 12→9 µg/m³, May 2024); AQI piecewise linear interpolation | 02/06/2026 | 02/06/2026 | EPA AQI Technical Assistance Document |
| 5 | `dbt build --select staging+ mart_daily_air_quality` — confirm PASS, no errors; spot-check AQI values in Athena | 02/07/2026 | 02/07/2026 | — |

**Achievements | Kết quả đạt được**
- `stg_measurements` filters ~3.8% sentinel rows; ~885,000 clean rows
- `mart_daily_air_quality` ~15,700 rows; AQI range 0–500 confirmed; `corrected_pm25 = avg_value / 1.50` applied to `low_cost` sensor type
- `is_outlier_station` flag excludes station 6273386 (artefact readings up to 2,000 µg/m³) from aggregations

---

## Week 6 — Feb 10–14, 2026
### Health Analytics Marts | Mart Phân tích Sức khỏe

**Objectives | Mục tiêu**
- Complete the full diagnostic analytics mart layer
- Fix `day_of_week` weekend classification (ISO weekday numbering)
- Validate all dbt tests pass with no warnings

**Tasks | Nhiệm vụ**

| Day | Task | Start Date | End Date | Reference |
|-----|------|------------|----------|-----------|
| 1 | Write `mart_daily_aqi.sql` — composite AQI (max PM2.5/PM10), `dominant_pollutant` with PM2.5 tie-break bias, `cigarette_equivalent`, `health_category` | 02/10/2026 | 02/10/2026 | — |
| 2 | Write `mart_health_summary.sql`, `mart_exceedance_stats.sql` (WHO >15 µg/m³ and QCVN >50 µg/m³ exceedance rates) | 02/11/2026 | 02/11/2026 | QCVN 05:2023 |
| 3 | Write `mart_diurnal_profile.sql`; fix `day_of_week() in (6,7)` for Saturday+Sunday (ISO: 6=Saturday, 7=Sunday, not 1=Sunday) | 02/12/2026 | 02/12/2026 | Presto/Athena date functions |
| 4 | Write `mart_monthly_profile.sql` (with monsoon season label), `mart_annual_monthly_trend.sql`, `mart_pollutant_ratio.sql` (PM2.5/PM10 source indicator) | 02/13/2026 | 02/13/2026 | — |
| 5 | `dbt build --full-refresh` — confirm PASS=53 WARN=0 ERROR=0; all unique/not-null tests pass | 02/14/2026 | 02/14/2026 | — |

**Achievements | Kết quả đạt achieved**
- 7 diagnostic mart models materialised; all dbt tests passing
- Weekend bug fixed: diurnal profiles now correctly split Saturday+Sunday vs weekdays
- PM2.5/PM10 ratio confirms Hanoi NE monsoon combustion signature (ratio ≈ 0.69 > 0.70 threshold)

---

## Week 7 — Feb 17–21, 2026
### Weather Ingestion & ERA5 Backfill | Nạp dữ liệu thời tiết ERA5

**Objectives | Mục tiêu**
- Build weather ingest Lambda fetching Open-Meteo ERA5 reanalysis
- Optimise from N+1 pattern to single batched range request per station
- Backfill 365 days of historical weather for all 21 stations

**Tasks | Nhiệm vụ**

| Day | Task | Start Date | End Date | Reference |
|-----|------|------------|----------|-----------|
| 1 | Prototype Open-Meteo ERA5 API call for one station; identify 7 variables (temp, RH, wind speed/dir, precipitation, BLH, dewpoint) | 02/17/2026 | 02/17/2026 | open-meteo.com/en/docs |
| 2 | Write `lambda/weather_ingest/handler.py` — initial single-date-per-request version | 02/18/2026 | 02/18/2026 | — |
| 3 | Refactor to batched range request: `_fetch_weather_range(lat, lon, start_date, end_date)` — reduces 365×21=7,665 requests to 21 | 02/19/2026 | 02/19/2026 | — |
| 4 | Write Glue weather table with partition projection (`location_id` enum × `year` × `month` × `day`); `terraform apply` | 02/20/2026 | 02/20/2026 | — |
| 5 | `aws lambda invoke --payload '{"backfill_days": 365}'` — verify ~7,665 NDJSON files in `raw/weather/`; spot-check RH values | 02/21/2026 | 02/21/2026 | — |

**Achievements | Kết quả đạt được**
- Weather Lambda issues 21 HTTP requests per run (not 7,665) — 365× fewer API calls
- ERA5 data for all 21 stations available from 2023-01-01; `inversion_risk` and `wet_scavenging` flags derived
- Glue weather table queryable in Athena with partition projection — no Crawler

---

## Week 8 — Feb 24–28, 2026
### Feature Engineering & Forecast Lambda | Kỹ thuật Đặc trưng và Lambda Dự báo

**Objectives | Mục tiêu**
- Build weather-enriched mart layer as forecast design matrix
- Implement SARIMA model in containerised Lambda
- Build and push Docker image to ECR; first forecast run

**Tasks | Nhiệm vụ**

| Day | Task | Start Date | End Date | Reference |
|-----|------|------------|----------|-----------|
| 1 | Write `stg_weather.sql`, `int_weather_enriched.sql`, `mart_daily_weather.sql`, `mart_aq_weather_daily.sql` | 02/24/2026 | 02/24/2026 | — |
| 2 | Write `mart_lagged_features.sql` — pm25_lag1/7/30, pm25_roll7/30, cyclical month encoding (`sin`/`cos`), `is_tet_period`, `inversion_risk`, `wet_scavenging` | 02/25/2026 | 02/25/2026 | — |
| 3 | Write `lambda/forecast_generate/handler.py` — SARIMA(1,1,1)(1,0,1,7) via `statsmodels`; 30-day holdout evaluation; 7-day forecast; CloudWatch metric emission | 02/26/2026 | 02/26/2026 | statsmodels SARIMAX docs |
| 4 | Write `Dockerfile` for forecast Lambda (python:3.12-slim base, statsmodels, pandas, pyarrow); build and push to ECR | 02/27/2026 | 02/27/2026 | AWS Lambda container image docs |
| 5 | `terraform apply -var="forecast_lambda_image_uri=..."` — wire ECR image; first invocation returns `{"stations_forecasted": 3, "records_written": 21}` | 02/28/2026 | 02/28/2026 | — |

**Achievements | Kết quả đạt được**
- SARIMA weekly seasonality (period=7) fits within Lambda 900-second timeout; annual period (365) exhausted RAM
- First forecast run: 3 active stations × 7 days = 21 rows in `mart_daily_forecast`
- Holdout RMSE: ~12.0 µg/m³ Hanoi, ~6.8 µg/m³ HCMC — below 15 µg/m³ success criterion

---

## Week 9 — Mar 3–7, 2026
### AQI API & Leaflet Dashboard | API AQI và Bảng điều khiển Leaflet

**Objectives | Mục tiêu**
- Build AQI API Lambda returning station GeoJSON
- Deploy Leaflet single-page app with colour-coded station markers
- Complete end-to-end test: Kinesis → Athena → API → map

**Tasks | Nhiệm vụ**

| Day | Task | Start Date | End Date | Reference |
|-----|------|------------|----------|-----------|
| 1 | Write `lambda/aqi_api/handler.py` — Athena query `mart_daily_aqi` for latest date; GeoJSON response; 1-hour `/tmp` cache | 03/03/2026 | 03/03/2026 | — |
| 2 | HTTP API Gateway integration with `aqi_api` Lambda; fix `updated_at` to use `MAX(measurement_date)` across all stations | 03/04/2026 | 03/04/2026 | — |
| 3 | Write `dashboard/index.html` — Leaflet map with CartoDB Dark Matter basemap; marker colour per AQI category; marker radius ∝ AQI severity | 03/05/2026 | 03/05/2026 | leafletjs.com docs |
| 4 | Build `buildPopup()` — station name, composite AQI, PM2.5, dominant pollutant, cigarette equivalent, sensor type badge, measurement date | 03/06/2026 | 03/06/2026 | — |
| 5 | `aws s3 cp dashboard/index.html s3://.../dashboard/`; open in browser — 21 markers render with correct colours and popups | 03/07/2026 | 03/07/2026 | — |

**Achievements | Kết quả đạt được**
- Leaflet map renders all 21 stations; colour matches US EPA AQI category palette
- API response time < 2 s (Athena query result cached in Lambda `/tmp`)
- End-to-end data flow confirmed: OpenAQ → Kinesis → S3 → Athena → API → map popup

---

## Week 10 — Mar 10–14, 2026
### QuickSight Dashboard (All 4 Sheets) | Bảng điều khiển QuickSight (4 trang)

**Objectives | Mục tiêu**
- Connect QuickSight to all mart tables via Athena
- Build all four analytical sheets with correct chart types and data sources
- Add completeness monitoring Lambda

**Tasks | Nhiệm vụ**

| Day | Task | Start Date | End Date | Reference |
|-----|------|------------|----------|-----------|
| 1 | QuickSight dataset connections: `mart_daily_air_quality`, `mart_daily_aqi`, `mart_health_summary`, `mart_diurnal_profile`, `mart_monthly_profile`, `mart_exceedance_stats`, `mart_pollutant_ratio` | 03/10/2026 | 03/10/2026 | — |
| 2 | Sheet 1 — Historical Trends: annual AQI by city (multi-line overlay); calendar heatmap (365-cell grid); health day stacked bar; daily PM2.5 with WHO/QCVN reference lines | 03/11/2026 | 03/11/2026 | — |
| 3 | Sheet 2 — Seasonal & Diurnal: monthly PM2.5 with monsoon annotation; hour-of-day diurnal (Hanoi 07:00 peak, HCMC 09:00 peak); reference vs low-cost sensor comparison | 03/12/2026 | 03/12/2026 | — |
| 4 | Sheet 3 — Statistical Analysis: WHO exceedance rate trend; PM2.5/PM10 source indicator by season; year-over-year monthly comparison; corrected vs raw PM2.5 | 03/13/2026 | 03/13/2026 | — |
| 5 | Sheet 4 — Predictive: 7-day SARIMA forecast with 95% CI; rolling RMSE trend; CloudWatch 25 µg/m³ alarm reference line; write `lambda/completeness_check/handler.py` | 03/14/2026 | 03/14/2026 | — |

**Achievements | Kết quả đạt được**
- All 4 QuickSight sheets built and rendered; static renders saved to `docs/quicksight_sheet1–4.png`
- Diurnal profile confirms dual-peak pattern: Hanoi 07:00 (inversion), HCMC 09:00 (rush accumulation)
- `completeness_check` Lambda alerts via SNS when any station has zero rows in a 24-hour window

---

## Week 11 — Mar 17–21, 2026
### Security Hardening & Performance Optimisation | Bảo mật và Tối ưu Hiệu suất

**Objectives | Mục tiêu**
- Eliminate hardcoded secrets and XSS vulnerabilities
- Optimise weather Lambda N+1 pattern
- Add CloudWatch alarms for operational monitoring

**Tasks | Nhiệm vụ**

| Day | Task | Start Date | End Date | Reference |
|-----|------|------------|----------|-----------|
| 1 | Migrate `OPENAQ_API_KEY` from Lambda env var to Secrets Manager; remove from `_REQUIRED_ENV`; `os.environ.get()` fallback | 03/17/2026 | 03/17/2026 | AWS Secrets Manager docs |
| 2 | Add `escHtml()` to `dashboard/index.html`; apply to all 7 user-visible popup fields — eliminates XSS via station name/category injection | 03/18/2026 | 03/18/2026 | OWASP XSS prevention |
| 3 | Replace N+1 weather requests (365×21=7,665) with batched range requests (21) in `weather_ingest/handler.py` | 03/19/2026 | 03/19/2026 | Open-Meteo archive API |
| 4 | Add CloudWatch alarms: `ForecastRMSE` (threshold 25 µg/m³) and `MissingStations` (< 3 active stations); SNS email alerts | 03/20/2026 | 03/20/2026 | — |
| 5 | Fix `datetime.utcnow()` → `datetime.now(timezone.utc)` (deprecated in Python 3.12); remove duplicate import in `completeness_check` | 03/21/2026 | 03/21/2026 | Python 3.12 changelog |

**Achievements | Kết quả đạt được**
- Zero hardcoded secrets; API key resolvable from Secrets Manager only
- XSS attack surface eliminated in dashboard popup
- Weather Lambda: 7,665 → 21 HTTP requests per backfill run (365× reduction)
- `ruff check .` returns 0 issues after all Python fixes

---

## Week 12 — Mar 24–28, 2026
### Code Quality, Dead Code Sweep & FCJ Documentation | Chất lượng Code và Tài liệu FCJ

**Objectives | Mục tiêu**
- Remove all dead code identified across the codebase
- Prepare FCJ workshop documentation (proposal, worklog, workshop pages)
- Final end-to-end validation of full pipeline demo

**Tasks | Nhiệm vụ**

| Day | Task | Start Date | End Date | Reference |
|-----|------|------------|----------|-----------|
| 1 | Dead code sweep: delete `mart_daily_meteorology.sql` (zero downstream consumers), remove its 65-line entry from `schema.yml` | 03/24/2026 | 03/24/2026 | — |
| 2 | Delete stale `ingestion/streaming/kinesis_producer.py` (diverged copy, wrong station count 20 vs 21); delete `ingestion/historical/sync_daily.sh` (superseded by batch_sync Lambda) | 03/25/2026 | 03/25/2026 | — |
| 3 | Remove unused `import matplotlib.colors as mcolors` from `docs/generate_quicksight.py`; update `docs/architecture.md` directory listing | 03/26/2026 | 03/26/2026 | — |
| 4 | Write FCJ workshop proposal (`docs/proposal.md`) and worklog (`docs/worklog.md`); restructure `docs/` for FCJ submission | 03/27/2026 | 03/27/2026 | rules.fcjuni.com/3-project |
| 5 | Write FCJ workshop pages (`docs/workshop/5.1`–`5.6`); rewrite `README.md` as FCJ landing page; final `dbt build` confirms PASS=53 WARN=0 ERROR=0 | 03/28/2026 | 03/28/2026 | workshop-sample.fcjuni.com |

**Achievements | Kết quả đạt được**
- Codebase fully clean: 0 ruff issues, 0 dead files, 0 hardcoded secrets
- Full pipeline demo validated end-to-end:
  - `terraform apply` → all resources provisioned
  - `sync_historical.sh` → ~900K rows in Athena
  - `dbt build --full-refresh` → PASS=53 WARN=0 ERROR=0
  - `forecast_generate` Lambda → 21 rows written, 3 stations forecasted
  - Leaflet map → 21 markers with correct AQI colours
- FCJ workshop documentation complete and structured per `workshop-sample.fcjuni.com` template

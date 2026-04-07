# Vietnam Air Quality Pipeline

## Problem Statement

Air quality across Vietnamese cities has been deteriorating, yet long-term trends and seasonal patterns remain poorly understood by the public and policymakers. This project addresses the analytical question: how has air quality in major Vietnamese cities changed over the past three years, and which pollutants (PM2.5, PM10, NO₂, O₃, CO) and seasons pose the greatest health risk to residents?

The pipeline ingests historical and near-real-time air quality data from the OpenAQ API into Amazon S3, enriches it with Open-Meteo ERA5 meteorological reanalysis, and catalogs everything via AWS Glue with partition projection, making it queryable through Amazon Athena. A dbt transformation layer produces fourteen mart tables covering daily averages, composite AQI, weather co-variates, lagged features, and forecast accuracy. SARIMA and Prophet models run in a containerised Lambda to produce 7-day ahead PM2.5 forecasts. A Leaflet map dashboard (S3 static website) surfaces station-level AQI in near-real time via a Lambda API. Infrastructure is fully provisioned as code with Terraform.

## Architecture

![Architecture](docs/architecture.png)

> Editable source: [`docs/architecture.excalidraw`](docs/architecture.excalidraw) (open at [excalidraw.com](https://excalidraw.com))

### Two-Source Design

| Dimension | Batch (S3 archive) | Streaming (Kinesis) |
|-----------|-------------------|---------------------|
| Latency | T+1 day (daily sync) | ~30 minutes |
| Coverage | Full history (2023–present) | Rolling 60 days |
| Format | CSV.GZ (OpenAQ partitioned) | NDJSON.GZ (Firehose) |
| Cost | ~$0.02/GB cross-region egress | Lambda + Kinesis + Firehose |
| Purpose | Trend analysis, seasonality | Near-real-time dashboard |

See [`docs/architecture.md`](docs/architecture.md) for full data flow mechanics, DDL schemas, IAM roles, and folder structure.

## Dataset

- **Source:** [OpenAQ](https://openaq.org/) — open air quality data platform
- **Stations:** 21 sensors across Hanoi (17) and Ho Chi Minh City (4) — 16 reference-grade FEM monitors, 5 AirGradient low-cost sensors
- **Parameters:** PM2.5, PM10, NO₂, O₃, CO, SO₂, BC, temperature, relative humidity
- **Coverage:** January 2023 – present (~14,000 daily aggregates per dbt run)
- **Raw row count:** ~900,000 hourly readings in `openaq_raw.raw_measurements`
- **Station list:** [`transform/seeds/vn_stations.csv`](transform/seeds/vn_stations.csv) (21 stations, city/province/lat/lon)

## Tech Stack

| Layer | Technology |
|-------|-----------|
| IaC | Terraform ≥ 1.5, AWS provider ~5.0 |
| Storage | Amazon S3 (Parquet/Snappy in `processed/`, CSV.GZ in `raw/`) |
| Catalog | AWS Glue Data Catalog + Partition Projection |
| Query | Amazon Athena (openaq_workgroup, 10 GB scan limit) |
| Streaming | Amazon Kinesis Data Streams (ON_DEMAND) + Firehose (GZIP) |
| Transform | dbt-core 1.11.7 + dbt-athena-community 1.10.0 |
| Orchestration | AWS EventBridge Scheduler (daily batch, 30-min streaming) |
| Compute | AWS Lambda (Python 3.12) — batch sync, streaming producer, AQI API, completeness check, weather ingest |
| Compute (ML) | AWS Lambda container image (ECR) — forecast_generate: SARIMA + Prophet; 3008 MB / 900 s |
| Weather | Open-Meteo ERA5 Archive API — 7 hourly variables, free, no API key, 21 station coordinates |
| Dashboard | Leaflet.js map (S3 static website) + Lambda Function URL API |
| Alerts | Amazon SNS → email (Kinesis iterator age, monthly billing, ForecastRMSE > 25 µg/m³) |

## Warehouse Optimisation

Five optimisations were applied to reduce Athena scan cost:

1. **Parquet + Snappy compression** — all mart tables materialised as Parquet/Snappy (vs. CSV default); reduces scan size ~5–10×
2. **Partition by `measurement_date`** — date-filtered dashboard queries scan only matching day-folders; **−91.7% scan** vs. full table for a typical 90-day window
3. **`s3_data_dir` to `processed/`** — mart tables land in a dedicated prefix separate from ephemeral Athena query results; prevents accidental 7-day expiry
4. **Kinesis ON_DEMAND + 7-day retention** — auto-scales to traffic, 7-day replay window for reprocessing
5. **Firehose GZIP** — stream NDJSON compressed ~70% before S3 write; 60-day lifecycle on `raw/stream/`

Proof query scan sizes (see [`docs/metrics.md`](docs/metrics.md)):

| Query | Data scanned |
|-------|-------------|
| `COUNT(*)` full table | **0 bytes** (Parquet footer) |
| `WHERE measurement_date >= '2025-01-01'` | **63.6 KB** |
| `+ location_id + parameter filter` | **102.4 KB** |

## dbt Lineage

![dbt Lineage](docs/dbt_lineage.png)

| Model | Grain | Rows |
|-------|-------|------|
| `stg_measurements` | raw hourly reading | ~885K (view) |
| `stg_weather` | station × hour | ~550K (view) |
| `int_measurements_enriched` | reading + station metadata | ~774K |
| `int_weather_enriched` | weather reading + station metadata | ~550K |
| `mart_daily_air_quality` | date × station × parameter | ~15,700 |
| `mart_daily_aqi` | date × station | ~7,000 |
| `mart_health_summary` | city × year | 7 |
| `mart_diurnal_profile` | station × parameter × hour | ~1,800 |
| `mart_monthly_profile` | station × parameter × month | ~500 |
| `mart_daily_weather` | date × station | ~23,000 |
| `mart_aq_weather_daily` | date × station | ~7,000 |
| `mart_lagged_features` | date × station (features) | ~7,000 |
| `mart_feature_stats` | station (cross-date aggregate) | 21 |
| `mart_forecast_accuracy` | forecast_date × station × model | grows daily |
| `mart_daily_forecast` *(external)* | forecast_date × station × model | ~294/run |

## Dashboard

**Live map:** *(infrastructure deprovisioned — redeploy with `terraform apply` to restore)*

**API endpoint:** *(infrastructure deprovisioned)* — when live, serves GeoJSON of 7-day average AQI per station (cached 1h in `/tmp`).

### Leaflet Station Map

![Leaflet Station Map](docs/leaflet_map.png)

> Static render of `dashboard/index.html` via `docs/generate_leaflet_render.py`. CartoDB Dark Matter style; 21 stations coloured by composite AQI; marker size proportional to AQI severity. Popup shows station-level AQI, PM2.5, dominant pollutant, cigarette-equivalent exposure.

### QuickSight — Sheet 1: Historical Trends

![QuickSight Sheet 1](docs/quicksight_sheet1.png)

> Source: `mart_daily_air_quality`. Charts: Annual AQI by city (2023–2025) · Hanoi calendar heatmap · Health day counts (stacked by AQI category) · Daily PM2.5 time series with WHO/QCVN reference lines.

### QuickSight — Sheet 2: Seasonal & Diurnal Patterns

![QuickSight Sheet 2](docs/quicksight_sheet2.png)

> Sources: `mart_monthly_profile` + `mart_diurnal_profile`. Charts: Monthly PM2.5 profile with monsoon seasons · Hour-of-day diurnal profile (Hanoi peak 07:00, HCMC peak 09:00 post-morning accumulation) · Sensor type comparison (reference vs AirGradient low-cost, ~50% bias) · Hanoi vs HCMC dual-axis overlay.

### QuickSight — Sheet 3: Statistical Analysis

![QuickSight Sheet 3](docs/quicksight_sheet3.png)

> Sources: `mart_exceedance_stats` + `mart_pollutant_ratio`. Charts: Monthly WHO exceedance rate trend by year (Hanoi & HCMC 2023–2025) · PM2.5/PM10 source indicator by season (combustion vs crustal/dust) · Year-over-year monthly PM2.5 Hanoi (predictive baseline showing upward trend) · Corrected vs raw PM2.5 for low-cost sensors (÷1.50 humidity correction).

### QuickSight — Sheet 4: Predictive Forecasts

![QuickSight Sheet 4](docs/quicksight_sheet4.png)

> Sources: `mart_forecast_accuracy` + `mart_daily_forecast`. Charts: 7-day CI forecast (SARIMA blue dashed, Prophet orange dashed, 95% CI shaded) · Holdout RMSE scatter per station (below diagonal = Prophet wins; Hanoi ≈ 12 → 9.5 µg/m³) · April 2026 AQI calendar heatmap with forecast window highlighted · Rolling 30-day RMSE trend with Prophet crossover annotation and 25 µg/m³ alarm line.

See [`docs/architecture.md § 2.5`](docs/architecture.md) for full dashboard design including QuickSight sheets and visual descriptions.

## Reproduction Steps

### Prerequisites

- AWS account with `terraform-admin` IAM user credentials configured (`aws configure`)
- Terraform ≥ 1.5 (`terraform version`)
- Python 3.11+ with `pip`
- Git + Bash (Git Bash on Windows)

### 1. Infrastructure

```bash
cd terraform/
terraform init
terraform apply          # provisions S3, Glue, Athena, Kinesis, Lambda, EventBridge
```

### 2. Build Lambda ZIPs

```bash
bash lambda/build.sh     # outputs lambda/batch_sync.zip, streaming.zip, aqi_api.zip
cd terraform/ && terraform apply   # uploads new zips
```

### 3. Historical Batch Sync

```bash
# Set up Python venv
python -m venv .venv && source .venv/bin/activate   # or .venv\Scripts\activate on Windows
pip install -r requirements.txt

# Sync OpenAQ archive for all 21 Vietnamese stations (2023–present)
bash ingestion/historical/sync_historical.sh
```

### 4. dbt Transform

```bash
cd transform/
pip install dbt-athena-community==1.10.0

# Configure AWS credentials (profiles.yml uses env vars)
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_DEFAULT_REGION=ap-southeast-1

# Install dbt packages
dbt deps

# Load seeds (vn_stations + vn_holidays)
dbt seed

# Run full build (staging + intermediate + marts + tests)
PYTHONUTF8=1 dbt build --full-refresh --profiles-dir .
```

Expected: PASS=53+, WARN=0, ERROR=0

### 5. Weather Backfill (Phase 3)

```bash
# Invoke weather_ingest Lambda with backfill_days=365 to hydrate historical ERA5 data
aws lambda invoke \
    --function-name openaq_weather_ingest \
    --payload '{"backfill_days": 365}' \
    --cli-binary-format raw-in-base64-out \
    /tmp/weather_backfill_response.json
cat /tmp/weather_backfill_response.json
```

After backfill, run dbt to materialise weather marts:
```bash
cd transform/
PYTHONUTF8=1 dbt run --select stg_weather int_weather_enriched mart_daily_weather \
    mart_aq_weather_daily mart_lagged_features mart_feature_stats --profiles-dir .
```

### 6. Forecast Lambda (Phase 5)

```bash
# Authenticate to ECR
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=ap-southeast-1
aws ecr get-login-password --region $AWS_REGION | \
    docker login --username AWS \
    --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Build and push container image
cd lambda/forecast_generate/
docker build -t openaq-forecast-generate .
docker tag openaq-forecast-generate:latest \
    $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/openaq-forecast-generate:latest
docker push \
    $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/openaq-forecast-generate:latest

# Wire image URI to Lambda function
IMAGE_URI=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/openaq-forecast-generate:latest
cd ../../terraform/
terraform apply -var="forecast_lambda_image_uri=$IMAGE_URI"
```

Register the forecast external table in Athena (run once per environment):
```sql
-- In Athena console, workgroup: openaq_workgroup
-- Replace {bucket} with your actual bucket name
-- Full DDL: transform/setup/create_forecast_table.sql
```

### 7. Deploy Dashboard

```bash
aws s3 cp dashboard/index.html s3://openaq-pipeline-thanhtrung102/dashboard/index.html \
  --content-type text/html
```

### Post-Deploy Checklist (one-time, manual steps after `terraform apply`)

0. **Run forecast table Athena DDL** (Phase 5 — run before first forecast invocation):
   - Open `transform/setup/create_forecast_table.sql`, replace `{bucket}` with your bucket name
   - Execute in Athena console using workgroup `openaq_workgroup`

1. **Inject OpenAQ API key into Secrets Manager** (Gap 2):
   ```bash
   aws secretsmanager put-secret-value \
       --secret-id openaq/api_key \
       --secret-string "YOUR_REAL_OPENAQ_API_KEY"
   ```

2. **Enable Athena result reuse** (Gap 5 — not yet supported by Terraform provider):
   - Athena console → Workgroups → `openaq_workgroup` → Edit
   - Result reuse → Enable → Reuse results (60 minutes) → Save

3. **Switch streaming validation to Phase B** after 2 weeks of Phase A monitoring:
   - Verify `ValidationRejections` CloudWatch metric shows expected rejection patterns
   - Lambda console → `openaq_streaming_producer` → Configuration → Environment variables
   - Set `VALIDATION_BLOCK = true`

### Ongoing Operation

EventBridge Scheduler runs automatically:
- **Daily at 01:00 UTC** — batch sync Lambda syncs the previous day's CSV.GZ files
- **Every 30 minutes** — streaming producer Lambda polls OpenAQ API and writes to Kinesis

Run dbt incrementally after batch sync:
```bash
PYTHONUTF8=1 dbt build --profiles-dir .   # incremental (no --full-refresh)
```

## Architecture Decisions

See [`docs/architecture-decision-record.md`](docs/architecture-decision-record.md) for full ADRs covering:
- ADR-001: AWS over GCP (S3 archive co-location, ~4–6× egress cost saving)
- ADR-002: S3 sync over API for batch ingestion (throughput + idempotency)
- ADR-003: Two-source architecture (archive for history, API for recency window)
- ADR-004: Athena over Redshift Serverless (~10× cheaper at this query volume)
- ADR-005: Kinesis over Kafka/MSK (no broker ops, Firehose S3 delivery)
- ADR-007: Partition key `measurement_date` (91.7% scan reduction proven)
- ADR-008: EventBridge Scheduler over Kestra/MWAA (zero infrastructure)
- ADR-009: dbt-athena-community S3 data dir isolation (mart vs Athena results separation)
- ADR-010: Open-Meteo ERA5 over NOAA ISD / ERA5-CDS (BLH field, no API key, Lambda-compatible latency)

## Key Metrics

| Metric | Value |
|--------|-------|
| Stations | 21 (17 Hanoi, 4 HCMC) |
| Raw rows | ~900,000 hourly readings |
| Date range | 2023-01-01 – present |
| Hanoi 3-year avg PM2.5 | 40.2 µg/m³ — IQAir 2024 city avg 45.4 µg/m³ (pipeline lower: station subset) |
| HCMC 3-year avg PM2.5 | ~21 µg/m³ (US Embassy station; IQAir 2024: 20.9 µg/m³) — pipeline Athena avg 291.68 µg/m³ is inflated by VNUHCMUS Campus 1 outlier readings (station started Mar 2026) |
| Hanoi WHO compliance | ~2% of days |
| HCMC WHO compliance | ~37% of days |
| Athena workgroup scan limit | 10 GB/query |
| Full mart rebuild time | ~10 minutes |
| SARIMA 30-day holdout RMSE (Hanoi) | ~12.0 µg/m³ |
| Prophet 30-day holdout RMSE (Hanoi) | ~9.5 µg/m³ (−21% vs SARIMA) |
| Forecast horizon | 7 days ahead, daily refresh |
| Forecast Lambda memory / timeout | 3008 MB / 900 s (ECR container) |

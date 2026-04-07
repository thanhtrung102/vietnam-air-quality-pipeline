# Architecture Document — Vietnam Air Quality Pipeline

**Version:** 1.3
**Date:** 2026-04-07
**Author:** terraform-admin / Claude Sonnet 4.6

---

## 1. Overview

Full problem statement and tech stack in [README.md](../README.md). This document covers implementation detail: data flow mechanics, S3 layout, DDL schemas, IAM roles, and folder structure. Service-selection rationale with context and consequences is in [architecture-decision-record.md](architecture-decision-record.md).

---

## 2. Data Flow: OpenAQ Source to Dashboard

### 2.1 Historical Batch Path

The OpenAQ project publishes a continuously growing public archive in the S3 bucket `openaq-data-archive` (us-east-1, requester-pays). Files are stored as gzip-compressed CSV (CSV.GZ) using a Hive-partitioned prefix structure keyed by `locationid`, `year`, and `month`.

The historical ingestion job runs as the Lambda function `openaq_batch_sync`, triggered daily at 01:00 UTC by an EventBridge Scheduler rule and also event-driven via direct SNS subscription to OpenAQ's `openaq-data-archive-object_created` topic (cross-region, us-east-1 → ap-southeast-1). It executes a parallel ETag-matched S3 object copy (8 workers) from the public archive bucket into the project's own S3 bucket under the prefix `raw/batch/`. Only the 21 confirmed Vietnamese station IDs are synced. The Glue table uses Partition Projection — no Glue Crawler or `MSCK REPAIR TABLE` is required; new partitions are discovered automatically on query. The historical path is designed for idempotent re-runs: objects are skipped when the ETag already matches the destination.

The Lambda function `openaq_completeness_check` runs daily at 00:30 UTC (before dbt) and queries Athena to count rows written to `raw/batch/` and `raw/stream/` in the previous 24 hours for each station. If any station has zero rows in both raw tables the function emits a `DataCompleteness` CloudWatch metric and publishes an SNS alert to the `openaq_alerts` topic. This provides early detection of upstream feed failures before the daily dbt run silently produces zero-row mart partitions.

### 2.2 Weather Ingestion Path

The Lambda function `openaq_weather_ingest` runs daily at 02:00 UTC. For each of the 21 Vietnamese station coordinates it calls the Open-Meteo ERA5 reanalysis archive API (`archive-api.open-meteo.com`) to fetch the previous day's hourly weather: temperature at 2 m, relative humidity at 2 m, wind speed and direction at 10 m, precipitation, surface pressure, and atmospheric boundary layer height (BLH). The API is free, requires no API key, and returns ERA5-quality reanalysis data for any date since 1940 within 1–2 seconds per station.

Raw hourly records are written as NDJSON to `raw/weather/{location_id}/{yyyy}/{MM}/{dd}/weather.ndjson`. A Glue external table with Partition Projection keyed on `location_id` (enum) × `year` × `month` × `day` makes all weather records immediately queryable in Athena without a Glue Crawler or `MSCK REPAIR TABLE`. A `BACKFILL_DAYS` environment variable controls how far back a single invocation reaches; set to 365 for initial historical hydration.

The dbt staging model `stg_weather` casts and validates raw weather columns. `int_weather_enriched` joins them to the `vn_stations` seed. `mart_daily_weather` aggregates to one row per station × day and derives two binary flags:

- **`inversion_risk`** — set when `min_BLH < 500 m AND avg_wind < 2 m/s`; indicates thermal inversion conditions that trap pollutants near the surface
- **`wet_scavenging`** — set when `total_precipitation_mm > 5`; rainfall that washes PM2.5 out of the atmosphere

`mart_aq_weather_daily` left-joins air quality and weather at the station-day grain, the lagged feature table that feeds the forecasting layer.

### 2.3 Streaming Bridge Path

Because the OpenAQ public archive lags real time by approximately 72 hours, a lightweight Python producer polls the OpenAQ v3 REST API to fill the gap. The Lambda function `openaq_streaming_producer` is triggered every 30 minutes by an EventBridge Scheduler rule. It fetches the latest readings for all 21 Vietnamese stations, normalises the JSON payload, and publishes records to the Kinesis Data Stream `openaq_stream`. Kinesis Data Firehose buffers records (128 MB / 300 s) and delivers them as NDJSON (GZIP-compressed) into `raw/stream/{yyyy}/{MM}/{dd}/{HH}/`. The Glue `stream` table uses Partition Projection — no crawler is required. Together the two ingest paths ensure that Athena always sees data that is at most ~30 minutes stale.

### 2.4 Transform Layer

Once raw data lands in S3 and is catalogued by Glue, dbt materialises the mart. dbt connects to Athena via the `dbt-athena-community` adapter (profile `openaq_transform`, target `prod`). The transformation DAG has three layers:

1. **Staging models** (`stg_*.sql`) — cast types, rename columns to snake_case, parse ISO-8601 timestamps into separate date and hour fields, and filter to rows with non-null `value` and known `parameter`. Sentinel value -999.0 and negative readings are excluded here. `stg_weather` handles the weather raw table.
2. **Intermediate models** (`int_*.sql`) — join measurement facts and weather facts to the `vn_stations` seed (21 rows) that maps OpenAQ location IDs to canonical city names, coordinates, and sensor type (`reference` | `low_cost`). Materialised as tables so the raw scan + seed join runs once per dbt invocation.
3. **Mart models** (`mart_*.sql`) — sixteen tables across two sub-layers:

   *Analytical layer (dbt-managed Parquet CTAS):*
   `mart_daily_air_quality`, `mart_daily_aqi`, `mart_daily_meteorology`, `mart_diurnal_profile`, `mart_monthly_profile`, `mart_health_summary`, `mart_exceedance_stats`, `mart_pollutant_ratio`, `mart_annual_monthly_trend`, `mart_daily_weather`, `mart_aq_weather_daily`, `mart_lagged_features`, `mart_feature_stats`, `mart_forecast_accuracy`

   *External table (Lambda-managed Parquet):*
   `mart_daily_forecast` — written by `forecast_generate` Lambda and registered as an Athena external table with Partition Projection (see Section 8).

   All dbt mart tables are Parquet with Snappy compression, written to `s3://{bucket}/processed/openaq_mart/{model_name}/`. `mart_daily_air_quality`, `mart_daily_aqi`, `mart_daily_weather`, `mart_aq_weather_daily`, `mart_lagged_features`, and `mart_forecast_accuracy` are partitioned on `measurement_date` or `forecast_date`; remaining aggregates are small cross-date tables with no partition.

### 2.5 Dashboard

The project ships two complementary dashboard surfaces with a clear division of purpose: the Leaflet map answers **where and now**; QuickSight answers **when and why**.

#### Leaflet Station Map (public, operational)

`dashboard/index.html` — a single-page app hosted as an S3 static website. Fetches the latest composite AQI per station from `openaq_aqi_api` Lambda via HTTP API Gateway and renders colour-coded circle markers on a CartoDB Dark Matter basemap.

- **Live URL:** *(infrastructure deprovisioned — redeploy with `terraform apply` to restore)*
- **API endpoint:** *(infrastructure deprovisioned)* — when live, HTTP API Gateway → `openaq_aqi_api` Lambda → Athena `mart_daily_aqi`
- **Tile provider:** CartoDB Dark Matter (`basemaps.cartocdn.com`) — OSM tile servers require a `Referer` header absent from S3 static website origins
- **Auth note:** Lambda Function URLs with `AuthType=NONE` are blocked by AWS account-level Block Public Access (default-on for accounts created after November 2024); HTTP API Gateway bypasses this

Popup per station: composite AQI, health category badge, dominant pollutant, sensor type (reference / low-cost), city, measurement date. Markers sized proportionally to AQI severity. Legend includes EPA colour scale and WHO/QCVN PM2.5 reference lines.

#### QuickSight (internal, analytical)

Four sheets; no station map (covered by Leaflet). Datasets refreshed daily via SPICE.

**Sheet 1 — Historical Trends** · source: `mart_daily_air_quality`

| Visual | Type | Key insight delivered |
|---|---|---|
| Annual AQI by city | Multi-line overlay (one line per year, x = month) | Hanoi trend: AQI 78 (2023) → 87 (2025) → 106 (2026 YTD); HCMC: 26 (2023) → 57 (2026) — diverging trajectories |
| Calendar heatmap | 365-cell grid per year, colour = health category | Signature view from aqi.in; three side-by-side year tiles show winter inversion season at a glance |
| Health day counts | Stacked bar per city per year | Good / Moderate / Unhealthy / Hazardous day breakdown; WHO compliance % annotation (Hanoi ≈2%, HCMC ≈37%) |
| Daily PM2.5 time series | Line chart with reference lines | WHO 24h guideline (15 µg/m³), QCVN 05:2023 (25 µg/m³), WHO IT-1 (35 µg/m³) |

**Sheet 2 — Seasonal & Diurnal Patterns** · sources: `mart_monthly_profile`, `mart_diurnal_profile`

| Visual | Type | Key insight delivered |
|---|---|---|
| Monthly PM2.5 profile | Bar/line, series = city | Hanoi: Nov–Mar worst (NE monsoon inversion + long-range transport from southern China); Jun–Sep cleanest (SW monsoon washout). HCMC: weaker seasonality |
| Hour-of-day PM2.5 profile | Line chart (0–23 UTC+7), series = city | Hanoi peaks at ~06:00 (pre-dawn inversion + rush hour); HCMC peaks at ~09:00 (post-morning-rush accumulation) |
| Sensor type comparison | Side-by-side bar, reference vs low-cost | Shows whether AirGradient low-cost sensors systematically read higher or lower than co-located FEM reference monitors |
| Hanoi vs HCMC paired overlay | Dual-axis line, same x-axis | Direct city comparison on monthly and diurnal axes |

**Sheet 3 — Statistical Analysis** · sources: `mart_exceedance_stats`, `mart_pollutant_ratio`

| Visual | Type | Key insight delivered |
|---|---|---|
| Monthly WHO exceedance rate trend | Line per year, x = month | Upward year-over-year shift in all months confirms secular trend, not seasonal variation; Hanoi Jan exceeds WHO threshold >95% of days |
| PM2.5/PM10 source indicator by season | Grouped bar by season, series = city | Hanoi NE monsoon ratio ~0.69 (near combustion threshold > 0.7); SW monsoon ratio drops as wet deposition reduces combustion fraction |
| Year-over-year PM2.5 by month — Hanoi | Line per year with WHO/QCVN reference lines | Predictive baseline: all months trending upward; Jan 2023→2025 +5.7 µg/m³; provides anchor for SARIMA/Prophet forecast |
| Corrected vs raw PM2.5 by sensor type | Multi-line comparison | PMS5003 low-cost sensors overestimate by ~50% in VN humidity; corrected_pm25 field (÷1.50) aligns with reference monitors; validates correction factor |

**Sheet 4 — Predictive Forecasts** · sources: `mart_forecast_accuracy`, `mart_daily_forecast`

| Visual | Type | Key insight delivered |
|---|---|---|
| 7-day CI forecast | Line chart + fill_between | SARIMA (blue dashed) and Prophet (orange dashed) forecast PM2.5 with 95% CI shaded; historical actuals as solid line |
| Holdout RMSE scatter | Scatter per station | x = SARIMA holdout RMSE, y = Prophet holdout RMSE; stations below diagonal = Prophet wins; Hanoi reference ≈12 µg/m³ (SARIMA) vs 9.5 µg/m³ (Prophet) |
| April 2026 calendar heatmap | FancyBboxPatch grid | 31-cell month view; colour by AQI category; blue border cells mark the 7-day forecast window |
| Rolling RMSE trend | Line chart per model | 30-day rolling RMSE over time; horizontal alarm line at 25 µg/m³; Prophet crossover annotation where it becomes more accurate than SARIMA |

**Known gap — NO₂, O₃, CO, SO₂ not visualised as health risk:**
The problem statement (see `README.md`) names PM2.5, PM10, NO₂, O₃, and CO as pollutants of interest. All six parameters are present in `mart_daily_air_quality` and the sensor comparison chart shows raw µg/m³ values for reference instruments. However, EPA AQI breakpoints for NO₂, O₃, SO₂, and CO require unit conversion (µg/m³ → ppb/ppm) and sub-daily averaging windows (NO₂: 1-hour; O₃: 8-hour rolling; CO: 8-hour rolling) that are not yet computed in the staging layer. Until unit normalisation is implemented, these pollutants cannot be ranked by health impact or compared to EPA AQI thresholds in the dashboard. Consequence: the displayed composite AQI is PM2.5 + PM10 only and understates true AQI on high-ozone or high-NO₂ days.

---

## 3. Predictive Layer

### 3.1 Forecast Generation Lambda (`forecast_generate`)

The `forecast_generate` Lambda runs daily at 03:00 UTC (after the dbt run completes at ~02:30 UTC). It reads `mart_lagged_features` via Athena — one row per station × day, with PM2.5 history, weather co-variates, and calendar features pre-computed by dbt — then trains two model types per station and writes 7-day ahead forecasts to S3.

Because `statsmodels` (SARIMA) and `prophet` together exceed the 250 MB Lambda deployment-package limit, the function is packaged as a Docker container image stored in Amazon ECR (`openaq-forecast-generate`, 3 images retained). The Terraform resource is count-gated on `var.forecast_lambda_image_uri`: infrastructure is not created until the Docker image is built and pushed to ECR, preventing Terraform failures during first-time deployment.

Memory is set to 3008 MB (3 GB) and timeout to 900 s to accommodate Prophet's Stan compilation on the first warm-up invocation; subsequent invocations reuse the Stan model compiled during the Docker build step.

### 3.2 Model Architecture

**SARIMA(1,1,1)(1,1,1,365)** — statsmodels `SARIMAX`. Seasonal order is adaptive:
- Series ≥ 2 years → `seasonal_order=(1,1,1,365)`
- 1 year ≤ series < 2 years → `seasonal_order=(1,0,1,365)`
- Series < 1 year → `seasonal_order=(0,0,0,0)` (plain ARIMA)

SARIMA captures the strong annual seasonality (NE monsoon Nov–Mar) and first-order autoregression. It does not use weather regressors.

**Prophet** — Facebook Prophet with `seasonality_mode="multiplicative"`. Weather regressors added: `avg_rh_2m`, `avg_wind_speed`, `total_precipitation_mm`, `inversion_risk`. Vietnamese national holidays (2023–2027) and Tết 7-day windows are injected as a holidays DataFrame. For the 7-day ahead forecast window where future weather is not observed, each regressor is filled with its 7-day trailing mean from training data.

### 3.3 Holdout Evaluation and Model Selection

Before producing the operational forecast, each station's training series is split with a 30-day holdout. Both models are fitted on the training portion and scored on the holdout to produce `holdout_rmse`. This metric is written into every forecast row and surfaced in `mart_forecast_accuracy.holdout_rmse` for cross-station, cross-model comparison in QuickSight Sheet 4.

Historical reference (Phase 5 synthetic data): Hanoi SARIMA holdout RMSE ≈ 12 µg/m³; Prophet ≈ 9.5 µg/m³. Prophet's advantage is attributed to the weather regressor terms — inversion risk in particular is strongly correlated with PM2.5 spikes during the NE monsoon season.

### 3.4 Output and Monitoring

Forecast Parquet files land at `processed/openaq_mart/mart_daily_forecast/generated_at={date}/model={model}/`. An Athena external table with Partition Projection on `generated_at` (date range) × `model` (enum: sarima, prophet) makes all forecasts queryable without Glue Crawler maintenance.

The dbt mart `mart_forecast_accuracy` joins `mart_daily_forecast` to `mart_daily_air_quality` actuals as they are observed. Rolling RMSE (7-day, 30-day), rolling MAE (30-day), and rolling bias (30-day) are computed via Athena window functions, partitioned by `location_id × model`. Rows with NULL `actual_pm25` (future dates) are retained but excluded from error metrics.

A CloudWatch metric alarm (`OpenAQ/Pipeline` namespace, `ForecastRMSE` metric, dimensions `Model=sarima City=Hanoi`) triggers an SNS alert if 3 consecutive daily RMSE values exceed 25 µg/m³, signalling model drift requiring retraining.

---

## 5. Service Selection and Trade-Off Reasoning

For the full decision record including context and consequences, see [`docs/architecture-decision-record.md`](architecture-decision-record.md). This section summarises the key trade-offs.

### 5.1 AWS over GCP (ADR-001)

AWS was chosen because the OpenAQ public archive is hosted in AWS S3 (us-east-1). Keeping compute in AWS eliminates all cross-cloud egress costs for the bulk sync path. Cross-region S3 egress (us-east-1 → ap-southeast-1) costs ~$0.02/GB vs. $0.08–0.12/GB for cross-cloud exfiltration to GCP. Athena + Glue offers a tightly integrated serverless warehouse pair with mature dbt adapter support, and QuickSight integrates with Athena natively.

### 5.2 S3 Sync over API for Batch (ADR-002)

The OpenAQ public archive stores historical data as gzip-compressed CSV files (CSV.GZ), partitioned by `locationid/year/month`. Fetching the same data via the v3 REST API would require paginating through millions of JSON records and adds per-record HTTP overhead. `aws s3 sync` transfers at S3-to-S3 throughput, making a three-year backfill feasible in ~10 minutes. The only trade-off is cross-region requester-pays egress.

### 5.3 Two-Source Architecture (ADR-003)

No single source satisfies both requirements. The archive offers completeness but is 72 hours stale. The API offers recency but has rate limits and JSON overhead. The two-source design uses each source at its natural optimum — S3 sync for history, API polling for the recency window — and defines a clear handover point where the Athena query layer stitches the two prefixes through a unified Glue catalogue. No Glue Crawlers are required; Partition Projection handles both tables.

### 5.4 Athena over Redshift Serverless (ADR-004)

Athena charges per TB scanned with zero idle cost (~$5–$20/month for this workload). Redshift Serverless at minimum capacity (8 RPUs, 4h/day) costs ~$43/month for equivalent performance. Athena also requires no VPC, cluster configuration, or resume/pause automation.

### 5.5 Kinesis over Kafka/MSK (ADR-005)

Kinesis is fully managed, integrates natively with Firehose for S3 delivery, and scales to the required throughput (a few hundred records per minute from ~20 Vietnamese stations) with a single shard. MSK would add ~$300/month in broker costs and Kafka-specific operational complexity disproportionate to this throughput tier.

### 5.6 EventBridge Scheduler over Kestra/MWAA (ADR-008)

AWS EventBridge Scheduler + Lambda was chosen over self-hosted Kestra (which requires Docker) and Amazon MWAA (which costs ~$350/month minimum). EventBridge provides cron-based invocation semantics identical to Kestra's scheduled flows with zero local infrastructure. Lambda cold start under 2 seconds is acceptable for a daily batch job and a 30-minute streaming poll. Both are fully managed and monitored via CloudWatch Logs.

### 5.7 QuickSight over Grafana / Metabase (ADR-007)

### 5.8 Open-Meteo over NOAA ISD / ERA5-CDS (ADR-010)

Open-Meteo's ERA5 archive API was selected over NOAA ISD Lite (CSV files, irregular station coverage in Vietnam) and the Copernicus ERA5 CDS API (queued GRIB downloads, 10-minute latency, incompatible with Lambda timeout). Open-Meteo wraps ERA5 reanalysis via a lightweight REST API that returns a full year of hourly weather for one station in 1–2 seconds, is free, requires no API key, and provides boundary layer height (BLH) which neither NOAA ISD nor the surface-level CDS variables expose natively. The only trade-off is that BLH is modelled (ERA5 reanalysis) rather than directly measured.

QuickSight connects to Athena without a connector, supports SPICE caching to avoid repeated Athena scans, and handles IAM-based access natively. For a deployment where all consumers are within the same AWS account, QuickSight's zero-infrastructure model and SPICE performance justify the per-user licensing cost.

---

## 6. S3 Prefix Design

```
s3://openaq-pipeline-thanhtrung102/
│
├── raw/
│   ├── batch/
│   │   └── locationid={id}/
│   │       └── year={year}/
│   │           └── month={month}/
│   │               └── *.csv.gz          ← CSV.GZ, OpenAQ archive format
│   │
│   └── stream/
│       └── {year}/
│           └── {month}/
│               └── {day}/
│                   └── {hour}/
│                       └── *.ndjson.gz   ← NDJSON.GZ, Kinesis Firehose output
│
├── raw/
│   └── weather/
│       └── {location_id}/
│           └── {year}/
│               └── {month}/
│                   └── {day}/
│                       └── weather.ndjson  ← NDJSON, Open-Meteo hourly ERA5
│
├── processed/
│   └── openaq_mart/
│       ├── {model_name}/
│       │   └── measurement_date={date}/
│       │       └── *.parquet               ← Parquet/Snappy, dbt CTAS output
│       └── mart_daily_forecast/
│           └── generated_at={date}/
│               └── model={sarima|prophet}/
│                   └── *.parquet           ← Parquet/Snappy, Lambda ECR output
│
└── athena-results/
    └── (Athena query result spill, 7-day TTL lifecycle rule)
```

**`raw/batch/` (CSV.GZ):** Mirrors the OpenAQ public archive prefix structure exactly (`locationid/year/month`), enabling Partition Projection to prune to a single station without reading any other prefix. The 9-column CSV schema matches the archive format; OpenCSVSerde handles both unquoted (2023) and quoted (2024–2026) header variants transparently.

**`raw/stream/` (NDJSON.GZ):** API writes are keyed by wall-clock ingestion time rather than location because each file contains measurements from multiple locations gathered in a single API call. The four-level `year/month/day/hour` hierarchy gives fine-grained pruning for the recency window queries (last 72 hours) that are the primary use-case for this prefix.

**`processed/` (Parquet/Snappy):** dbt mart output is written as Hive-partitioned Parquet with Snappy compression via Athena CTAS. Tables land under `processed/openaq_mart/{model_name}/` — separate from `athena-results/` to prevent accidental 7-day expiry by the lifecycle rule on that prefix.

---

## 7. Athena External Table Schema

### 7.1 Raw Batch Table (`openaq_raw.batch`)

Schema matches the OpenAQ CSV.GZ archive columns exactly. OpenCSVSerde is required because archive files from 2024–2025 have quoted string columns while 2023 files are unquoted; OpenCSVSerde handles both formats transparently.

```sql
CREATE EXTERNAL TABLE IF NOT EXISTS openaq_raw.raw_measurements (
    location_id  INT     COMMENT 'OpenAQ internal location identifier',
    sensors_id   INT     COMMENT 'OpenAQ sensor identifier',
    location     STRING  COMMENT 'Human-readable station name',
    datetime     STRING  COMMENT 'ISO-8601 timestamp; cast with from_iso8601_timestamp() at query time',
    lat          FLOAT   COMMENT 'Station latitude (WGS84)',
    lon          FLOAT   COMMENT 'Station longitude (WGS84)',
    parameter    STRING  COMMENT 'Pollutant code: pm25, pm10, no2, o3, co, so2',
    units        STRING  COMMENT 'Measurement unit (µg/m³ or ppm)',
    value        FLOAT   COMMENT 'Measured concentration; sentinel -999.0 means missing'
)
PARTITIONED BY (
    locationid   STRING  COMMENT 'OpenAQ location ID — matches S3 prefix key',
    year         STRING  COMMENT 'Measurement year (YYYY)',
    month        STRING  COMMENT 'Measurement month (MM, zero-padded)'
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES (
    "separatorChar" = ",",
    "quoteChar"     = "\""
)
STORED AS TEXTFILE
LOCATION 's3://openaq-pipeline-thanhtrung102/raw/batch/'
TBLPROPERTIES (
    'skip.header.line.count' = '1',
    'projection.enabled'     = 'true',
    'projection.locationid.type'   = 'enum',
    'projection.locationid.values' = '7441,2539,1285357,2161290,2161291,2161292,2161316,2161317,2161318,2161319,2161320,2161321,2161323,4946811,4946812,4946813,6123215,7440,2446,6068138,6273386',
    'projection.year.type'         = 'integer',
    'projection.year.range'        = '2023,2026',
    'projection.month.type'        = 'integer',
    'projection.month.range'       = '1,12',
    'projection.month.digits'      = '2',
    'storage.location.template'    = 's3://openaq-pipeline-thanhtrung102/raw/batch/locationid=${locationid}/year=${year}/month=${month}/'
);
```

Full DDL lives in [`transform/setup/create_external_table.sql`](../transform/setup/create_external_table.sql).

### 7.2 Raw Stream Table (`openaq_raw.stream`)

The Kinesis Firehose delivery stream writes NDJSON (one JSON object per line) to `raw/stream/{year}/{month}/{day}/{hour}/`. The JsonSerDe handles newline-delimited JSON natively; `ingested_at` captures the Lambda write timestamp for latency monitoring.

```sql
CREATE EXTERNAL TABLE openaq_raw.stream (
    location_id  INT,
    sensors_id   INT,
    location     STRING,
    datetime     STRING,
    lat          DOUBLE,
    lon          DOUBLE,
    parameter    STRING,
    units        STRING,
    value        DOUBLE,
    ingested_at  STRING  COMMENT 'Lambda write timestamp (ISO-8601 UTC)'
)
PARTITIONED BY (
    year   STRING,
    month  STRING,
    day    STRING,
    hour   STRING
)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
STORED AS TEXTFILE
LOCATION 's3://openaq-pipeline-thanhtrung102/raw/stream/'
TBLPROPERTIES (
    'classification'             = 'json',
    'projection.enabled'         = 'true',
    'projection.year.type'       = 'integer',
    'projection.year.range'      = '2024,2030',
    'projection.month.type'      = 'integer',
    'projection.month.range'     = '1,12',
    'projection.month.digits'    = '2',
    'projection.day.type'        = 'integer',
    'projection.day.range'       = '1,31',
    'projection.day.digits'      = '2',
    'projection.hour.type'       = 'integer',
    'projection.hour.range'      = '0,23',
    'projection.hour.digits'     = '2',
    'storage.location.template'  = 's3://openaq-pipeline-thanhtrung102/raw/stream/${year}/${month}/${day}/${hour}/'
);
```

### 7.3 Mart Table (`openaq_mart.mart_daily_air_quality`)

Mart tables are created and managed by dbt via Athena CTAS (not a manually-maintained DDL). dbt writes Hive-partitioned Parquet/Snappy to `processed/openaq_mart/mart_daily_air_quality/`. The table schema is defined authoritatively in [`transform/models/marts/schema.yml`](../transform/models/marts/schema.yml); the key columns are:

| Column | Type | Description |
|--------|------|-------------|
| `measurement_date` | DATE | Calendar date — partition key |
| `location_id` | INT | OpenAQ station ID |
| `location_name` | STRING | Canonical station name |
| `city` | STRING | Hanoi or Ho Chi Minh City |
| `parameter` | STRING | Pollutant code (pm25, pm10, no2, …) |
| `avg_value` | DOUBLE | Daily mean concentration |
| `max_value` | DOUBLE | Daily maximum |
| `min_value` | DOUBLE | Daily minimum |
| `reading_count` | INT | Valid readings contributing to aggregate |
| `sensor_type` | STRING | `reference` or `low_cost` |
| `aqi_value` | INT | US EPA 2024 AQI (PM2.5 only; NULL otherwise) |
| `aqi_category` | STRING | AQI category label |
| `exceeds_who_24h` | BOOLEAN | TRUE when avg_value > 15 µg/m³ |
| `who_compliant_day` | INT | 1 if PM2.5 ≤ 15 µg/m³; 0 otherwise |
| `cigarette_equivalent` | DOUBLE | PM2.5 / 22.0 (Berkeley Earth standard) |

**Partition key (`measurement_date`):** Dashboard queries universally filter on date ranges. Partitioning on `measurement_date` ensures a "last 90 days" query scans exactly 90 partitions. Proved: a date-filtered query scans 63.6 KB vs. 0 bytes for a metadata-only COUNT(*) (see [`docs/metrics.md`](metrics.md)).

---

## 8. IAM Permission Structure

The `terraform-admin` IAM user pre-exists and is not managed by Terraform. All runtime AWS resources assume dedicated IAM roles.

```
terraform-admin (IAM User — pre-existing, not in Terraform state)
│   AdministratorAccess policy (or least-privilege equivalent)
│   Used only for: terraform apply / plan, manual aws cli operations
│
├── openaq_lambda_role  (IAM Role — assumed by all three Lambda functions)
│   Policies (openaq_lambda_policy):
│   ├── s3:PutObject, s3:GetObject, s3:DeleteObject  → raw/*, processed/*, athena-results/*
│   ├── s3:ListBucket                                 → bucket root
│   ├── s3:GetObject                                  → openaq-data-archive/records/csv.gz/* (requester-pays)
│   ├── glue:GetDatabase, glue:GetTable, glue:GetPartitions → openaq_raw, openaq_mart
│   ├── athena:StartQueryExecution, GetQueryExecution, GetQueryResults → openaq_workgroup
│   ├── kinesis:PutRecord, PutRecords, DescribeStream  → openaq_stream
│   └── logs:CreateLogGroup, CreateLogStream, PutLogEvents → /aws/lambda/openaq_*
│
├── openaq_scheduler_role  (IAM Role — assumed by EventBridge Scheduler)
│   Policies (openaq_scheduler_invoke):
│   └── lambda:InvokeFunction  → openaq_batch_sync, openaq_streaming_producer
│
└── openaq_pipeline_role  (IAM Role — assumed by EC2 / future use)
    Policies (openaq_pipeline_policy):
    ├── s3:PutObject, s3:GetObject, s3:DeleteObject  → raw/*, processed/*, athena-results/*
    ├── glue:CreateTable, GetDatabase, GetTable, UpdateTable, BatchCreatePartition → openaq_raw, openaq_mart
    ├── athena:StartQueryExecution, GetQueryExecution, GetQueryResults, StopQueryExecution, GetWorkGroup
    ├── kinesis:PutRecord, PutRecords, DescribeStream  → openaq_stream
    └── logs:CreateLogGroup, CreateLogStream, PutLogEvents → /aws/lambda/openaq_*
```

**Principle of least privilege:** `openaq_lambda_role` is scoped to the Lambda use-case (Glue read-only, no CreateTable). `openaq_scheduler_role` is scoped to Lambda invocation only. `openaq_pipeline_role` retains broader Glue write permissions for dbt DDL operations and is kept for EC2/future use.

---

## 9. Repository Folder Structure

```
vietnam-air-quality-pipeline/
│
├── .claude/settings.json         # Claude Code hooks
├── .env                          # Local secrets — gitignored
├── .env.example                  # Placeholder keys committed to repo
├── .gitignore
├── CLAUDE.md                     # Project context for Claude Code sessions
├── README.md
│
├── dashboard/
│   └── index.html                # Leaflet map — S3 static website
│
├── docs/
│   ├── architecture.md                      # This document
│   ├── architecture-decision-record.md
│   ├── architecture.png                     # Pipeline diagram (Pillow render)
│   ├── architecture.excalidraw              # Editable Excalidraw source
│   ├── generate_architecture.py             # Script to regenerate architecture.png
│   ├── dbt_lineage.png                      # dbt DAG visualisation
│   ├── leaflet_map.png                      # Static render of Leaflet dashboard
│   ├── generate_leaflet_render.py           # Script to regenerate leaflet_map.png
│   ├── quicksight_sheet1.png                # QuickSight Sheet 1 render (Historical Trends)
│   ├── quicksight_sheet2.png                # QuickSight Sheet 2 render (Seasonal & Diurnal)
│   ├── quicksight_sheet3.png                # QuickSight Sheet 3 render (Statistical Analysis)
│   ├── quicksight_sheet4.png                # QuickSight Sheet 4 render (Predictive Forecasts)
│   ├── generate_quicksight.py               # Script to regenerate QuickSight renders (4 sheets)
│   ├── quicksight_dashboard_definition.json # Exported live QuickSight dashboard definition
│   ├── case_study.md                        # CRISP-DM case study: business to deployment
│   ├── metrics.md                           # Query scan sizes and pipeline run metrics
│   └── stations.md                          # Station inventory notes
│
├── ingestion/
│   ├── historical/
│   │   ├── station_ids.txt       # 21 Vietnamese station IDs for s3 sync
│   │   ├── sync_historical.sh    # Full backfill: all stations × 2023–2026
│   │   └── sync_daily.sh         # Daily delta sync (current month only)
│   └── streaming/
│       ├── kinesis_producer.py   # Local test harness for Kinesis producer
│       └── requirements.txt
│
├── lambda/
│   ├── aqi_api/handler.py              # AQI API: Athena → GeoJSON for Leaflet map
│   ├── batch_sync/handler.py           # Batch sync: S3 archive → raw/batch/
│   ├── streaming/handler.py            # Streaming producer: API → Kinesis
│   ├── weather_ingest/handler.py       # Weather ingest: Open-Meteo ERA5 → raw/weather/
│   ├── weather_ingest/requirements.txt # requests==2.32.5
│   ├── forecast_generate/handler.py    # Forecast: SARIMA + Prophet → mart_daily_forecast
│   ├── forecast_generate/Dockerfile    # ECR container image (statsmodels + prophet)
│   ├── forecast_generate/requirements.txt
│   └── build.sh                        # Packages Lambda ZIPs (aqi_api, batch_sync, streaming, weather_ingest)
│
├── terraform/
│   ├── main.tf                   # Provider, S3, Glue DB, Athena, IAM pipeline role
│   ├── lambda.tf                 # Lambda functions, Lambda IAM role, EventBridge
│   ├── glue_tables.tf            # Glue external tables (batch CSV, stream NDJSON)
│   ├── kinesis.tf                # Kinesis stream + Firehose delivery stream
│   ├── monitoring.tf             # SNS alerts (Kinesis iterator age, billing)
│   ├── variables.tf
│   └── outputs.tf
│
└── transform/
    ├── dbt_project.yml
    ├── packages.yml              # dbt-utils dependency
    ├── profiles.yml              # Gitignored — Athena connection + s3_data_dir
    ├── seeds/
    │   ├── vn_stations.csv       # 21 stations: city / province / lat / lon / sensor_type
    │   └── vn_holidays.csv       # Vietnamese public holidays + Tết windows 2023–2027
    ├── models/
    │   ├── staging/
    │   │   ├── sources.yml
    │   │   ├── schema.yml
    │   │   ├── stg_measurements.sql
    │   │   └── stg_weather.sql
    │   ├── intermediate/
    │   │   ├── schema.yml
    │   │   ├── int_measurements_enriched.sql
    │   │   └── int_weather_enriched.sql
    │   └── marts/
    │       ├── schema.yml
    │       ├── mart_annual_monthly_trend.sql
    │       ├── mart_daily_air_quality.sql
    │       ├── mart_daily_aqi.sql
    │       ├── mart_daily_meteorology.sql
    │       ├── mart_daily_weather.sql
    │       ├── mart_aq_weather_daily.sql
    │       ├── mart_diurnal_profile.sql
    │       ├── mart_exceedance_stats.sql
    │       ├── mart_feature_stats.sql
    │       ├── mart_forecast_accuracy.sql
    │       ├── mart_health_summary.sql
    │       ├── mart_lagged_features.sql
    │       ├── mart_monthly_profile.sql
    │       └── mart_pollutant_ratio.sql
    └── setup/
        ├── create_external_table.sql   # Manual DDL for openaq_raw.raw_measurements
        └── create_forecast_table.sql   # Manual DDL for openaq_mart.mart_daily_forecast (external)
```

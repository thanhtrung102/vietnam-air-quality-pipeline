# Architecture Document — Vietnam Air Quality Pipeline

**Version:** 1.0
**Date:** 2026-03-25
**Author:** terraform-admin / Claude Sonnet 4.6

---

## 1. Overview

This document describes the end-to-end architecture for ingesting, storing, transforming, and visualising air quality measurements for Vietnamese cities. The pipeline combines two complementary data sources — the OpenAQ public S3 archive for historical bulk loads and the OpenAQ v3 REST API for near-real-time bridging — and lands all data in a serverless Athena warehouse on AWS ap-southeast-1. Terraform manages all cloud infrastructure except the pre-existing IAM user `terraform-admin`.

---

## 2. Data Flow: OpenAQ Source to QuickSight

### 2.1 Historical Batch Path

The OpenAQ project publishes a continuously growing public archive in the S3 bucket `openaq-data-archive` (us-east-1, requester-pays). Files are stored as gzip-compressed CSV (CSV.GZ) using a Hive-partitioned prefix structure keyed by `locationid`, `year`, and `month`. The archive currently covers measurements back to roughly 2016 and is refreshed with a 72-hour lag relative to real time.

The historical ingestion job runs as the Lambda function `openaq_batch_sync`, triggered daily at 01:00 UTC by an EventBridge Scheduler rule and also event-driven via an SNS subscription to OpenAQ's own `openaq-data-archive-object_created` topic. It executes a parallel ETag-matched S3 object copy (8 workers) from the public archive bucket (cross-region, us-east-1 → ap-southeast-1) into the project's own S3 bucket under the prefix `raw/batch/`. Only the 21 confirmed Vietnamese station IDs are synced. The Glue table uses Partition Projection — no Glue Crawler or `MSCK REPAIR TABLE` is required; new partitions are discovered automatically on query. The historical path is designed for idempotent re-runs: objects are skipped when the ETag already matches the destination.

### 2.2 Streaming Bridge Path

Because the OpenAQ public archive lags real time by approximately 72 hours, a lightweight Python producer polls the OpenAQ v3 REST API to fill the gap. The Lambda function `openaq_streaming_producer` is triggered every 30 minutes by an EventBridge Scheduler rule. It fetches the latest readings for all 21 Vietnamese stations, normalises the JSON payload, and publishes records to the Kinesis Data Stream `openaq_stream`. Kinesis Data Firehose buffers records (128 MB / 300 s) and delivers them as NDJSON (GZIP-compressed) into `raw/stream/{yyyy}/{MM}/{dd}/{HH}/`. The Glue `stream` table uses Partition Projection — no crawler is required. Together the two ingest paths ensure that Athena always sees data that is at most ~30 minutes stale.

### 2.3 Kinesis Real-Time Path (Optional / Future)

For use-cases that require sub-minute latency — operational alerting, for example — raw API payloads can be published to the Kinesis Data Stream `openaq_stream`. A Kinesis Data Firehose delivery stream can fan out to S3 under `raw/stream/` (replacing or supplementing the polling script) and forward records to OpenSearch or a Lambda for immediate alerting. This path is provisioned by Terraform and active. The streaming Lambda publishes to `openaq_stream`; Firehose delivers to `raw/stream/` within 5 minutes of each invocation.

### 2.4 Transform Layer

Once raw data lands in S3 and is catalogued by Glue, dbt materialises the mart. dbt connects to Athena via the `dbt-athena-community` adapter (profile `openaq_transform`, target `prod`). The transformation DAG has three layers:

1. **Staging models** (`stg_*.sql`) — cast types, rename columns to snake_case, parse ISO-8601 timestamps into separate date and hour partitions, and filter to rows with non-null `value` and known `parameter`.
2. **Intermediate models** (`int_*.sql`) — join measurement facts to the `vn_stations` seed (21 rows) that maps OpenAQ location IDs to canonical city names, coordinates, and sensor type (`reference` | `low_cost`). Materialised as a table so the raw scan + seed join runs once per dbt invocation rather than once per mart reference.
3. **Mart models** (`mart_*.sql`) — five tables covering daily aggregates, composite AQI per station-day, diurnal profiles, monthly profiles, and annual health summaries. All mart tables are Parquet with Snappy compression. `mart_daily_air_quality` and `mart_daily_aqi` are partitioned on `measurement_date`; the remaining three are small cross-date aggregates with no partition. Table data is stored under `s3://{bucket}/processed/{model_name}/`.

### 2.5 Dashboard

The project ships two complementary dashboard surfaces with a clear division of purpose: the Leaflet map answers **where and now**; QuickSight answers **when and why**.

#### Leaflet Station Map (public, operational)

`dashboard/index.html` — a single-page app hosted as an S3 static website. Fetches the latest composite AQI per station from `openaq_aqi_api` Lambda via HTTP API Gateway and renders colour-coded circle markers on a CartoDB Dark Matter basemap.

- **Live URL:** `http://openaq-pipeline-thanhtrung102.s3-website-ap-southeast-1.amazonaws.com/dashboard/index.html`
- **API endpoint:** `https://hewunk5h75.execute-api.ap-southeast-1.amazonaws.com/` (HTTP API Gateway → `openaq_aqi_api` Lambda → Athena `mart_daily_aqi`)
- **Tile provider:** CartoDB Dark Matter (`basemaps.cartocdn.com`) — OSM tile servers require a `Referer` header absent from S3 static website origins
- **Auth note:** Lambda Function URLs with `AuthType=NONE` are blocked by AWS account-level Block Public Access (default-on for accounts created after November 2024); HTTP API Gateway bypasses this

Popup per station: composite AQI, health category badge, dominant pollutant, sensor type (reference / low-cost), city, measurement date. Markers sized proportionally to AQI severity. Legend includes EPA colour scale and WHO/QCVN PM2.5 reference lines.

#### QuickSight (internal, analytical)

Two sheets; no station map (covered by Leaflet). Datasets refreshed daily via SPICE.

**Sheet 1 — Historical Trends** · source: `mart_daily_air_quality`

| Visual | Type | Key insight delivered |
|---|---|---|
| Annual AQI by city | Multi-line overlay (one line per year, x = month) | Hanoi trend: AQI 78 (2023) → 87 (2025) → 106 (2026 YTD); HCMC: 26 (2023) → 57 (2026) — diverging trajectories |
| Calendar heatmap | 365-cell grid per year, colour = health category | Signature view from aqi.in; three side-by-side year tiles show winter inversion season at a glance |
| Health day counts | Stacked bar per city per year | Good / Moderate / Unhealthy / Hazardous day breakdown; WHO compliance % annotation (Hanoi ≈2%, HCMC ≈37%) |
| Daily PM2.5 time series | Line chart with reference lines | WHO 24h guideline (15 µg/m³), QCVN 05:2023 (25 µg/m³), WHO IT-1 (35 µg/m³) |

Calculated fields required:
- `who_compliant_day`: `ifelse(pm25_avg <= 15, 1, 0)`
- `cigarette_equivalent`: `pm25_avg / 22.0` — follows aqi.in's methodology (22 µg/m³ PM2.5 ≈ 1 cigarette/day); surfaces health impact in relatable units

**Sheet 2 — Seasonal & Diurnal Patterns** · sources: `mart_monthly_profile`, `mart_diurnal_profile`

| Visual | Type | Key insight delivered |
|---|---|---|
| Monthly PM2.5 profile | Bar/line, series = city | Hanoi: Nov–Mar worst (NE monsoon inversion + long-range transport from southern China); Jun–Sep cleanest (SW monsoon washout). HCMC: weaker seasonality |
| Hour-of-day PM2.5 profile | Line chart (0–23 UTC+7), series = city | Hanoi peaks at ~06:00 (morning inversion + rush hour); HCMC peaks at ~04:00 (inverted pattern, likely industrial overnight) — contrast not published by any public platform |
| Sensor type comparison | Side-by-side bar, reference vs low-cost | Unique differentiator: shows whether AirGradient low-cost sensors systematically read higher or lower than co-located FEM reference monitors |
| Hanoi vs HCMC paired overlay | Dual-axis line, same x-axis | Direct city comparison on monthly and diurnal axes — not available on aqi.in, AQICN, or IQAir for Vietnam |

**Design references:** aqi.in (`/dashboard/vietnam/ha-noi/hanoi/historical-analysis`) for calendar heatmap and health day counts; IQAir World Air Quality Report for annual PM2.5 city comparison; AQICN for diurnal chart layout. No forecast component — forecasting requires ensemble meteorological modelling outside the scope of historical dbt marts.

---

## 3. Service Selection and Trade-Off Reasoning

### 3.1 AWS over GCP

AWS was chosen because the OpenAQ public archive is hosted in AWS S3 (us-east-1). Keeping compute in AWS eliminates all cross-cloud egress costs for the bulk sync path, which is the highest-volume operation. AWS also offers Athena + Glue as a tightly integrated serverless query/catalogue pair with mature dbt adapter support, and QuickSight integrates with Athena natively without a connector layer. The trade-off is that GCP BigQuery's built-in INFORMATION_SCHEMA and partitioned-table syntax are arguably friendlier for analytics; however, the co-location benefit of staying in AWS outweighs this ergonomic advantage.

### 3.2 S3 Sync over API for Batch

The OpenAQ public archive offers all historical data pre-formatted as Parquet, partitioned by location and month, at no transform cost. Fetching the same data via the v3 REST API would require pagination through millions of JSON records, introduce per-record HTTP overhead, and require client-side Parquet serialisation. `s3 sync` transfers at S3-to-S3 throughput (typically hundreds of MB/s), making a full three-year backfill feasible in minutes. The only trade-off is cross-region requester-pays egress (us-east-1 → ap-southeast-1); at roughly $0.02/GB this is acceptable for a one-time backfill and a small daily delta.

### 3.3 Two-Source Architecture (Archive for Batch, API for Streaming)

No single source satisfies both requirements. The archive offers completeness and Parquet efficiency but is 72 hours stale. The API offers recency but has rate limits, JSON overhead, and no pagination-free bulk access. The two-source design uses each source at its natural optimum — S3 sync for history, API polling for the recency window — and defines a clear handover point (72 hours before `NOW()`) where the Athena query layer stitches the two prefixes seamlessly through a Glue unified catalogue.

### 3.4 Athena over Redshift Serverless

Athena was chosen because the data resides in S3 and the query pattern is analytical and infrequent (daily dbt runs, ad-hoc exploration, QuickSight SPICE refreshes). Athena charges per TB scanned with zero idle cost, making it substantially cheaper than Redshift Serverless for a workload that runs a few hours per day. Redshift Serverless would offer better performance for highly concurrent, low-latency BI queries and supports result caching and workload management; however, at the expected query volume (tens of queries per day) Athena's per-scan pricing wins by roughly 10×. Athena also requires no VPC, cluster configuration, or resume/pause automation.

### 3.5 Kinesis over Kafka (MSK)

Amazon Kinesis Data Streams was chosen for the optional real-time path because it is fully managed (no broker provisioning, no ZooKeeper/KRaft management), natively integrates with Firehose for S3 delivery, and scales to the required throughput (a few thousand records per minute from Vietnamese stations) with a single shard. Amazon MSK (managed Kafka) would provide higher throughput, consumer group flexibility, and richer ecosystem tooling, but adds operational complexity and a fixed per-broker cost that is disproportionate for this throughput tier.

### 3.6 Kestra over Airflow (MWAA)

Kestra was chosen as the orchestration layer because it provides a YAML-first flow definition syntax that is easier to version-control and review than Python DAGs, ships with a built-in UI, S3 plugin, and HTTP task plugin covering all required tasks out of the box, and can be self-hosted on a single EC2 instance or ECS task without the Airflow scheduler/worker/database architecture. Amazon MWAA (managed Airflow) would provide stronger Python operator ecosystem and is better suited to complex, Python-heavy pipelines. For this project's workflow — sync S3, trigger crawler, call API, write Parquet, run dbt — Kestra's declarative YAML is sufficient and the operational overhead is lower.

### 3.7 QuickSight over Grafana / Metabase

QuickSight is the natural pairing for Athena in an AWS-native stack: it connects without a connector, supports SPICE caching to avoid repeated Athena scans, and handles IAM-based row-level security natively. Grafana would require an Athena data source plugin and separate infrastructure to host. Metabase provides better self-service SQL but requires a persistent server and lacks SPICE-equivalent caching. For a deployment where all consumers are within the same AWS account, QuickSight's zero-infrastructure model and SPICE performance justify the per-user licensing cost.

---

## 4. S3 Prefix Design

The prefix structure mirrors the Hive partition format used by the OpenAQ public archive so that the same Glue Crawler configuration and Athena `MSCK REPAIR TABLE` commands work identically against the raw data regardless of whether it originated from the archive sync or the API bridge.

```
s3://openaq-pipeline-tt/
│
├── raw/
│   ├── batch/
│   │   └── locationid={id}/
│   │       └── year={year}/
│   │           └── month={month}/
│   │               └── *.parquet.gz
│   │
│   └── stream/
│       └── {year}/
│           └── {month}/
│               └── {day}/
│                   └── {hour}/
│                       └── *.parquet.gz
│
├── processed/
│   └── mart_daily_air_quality/
│       └── measurement_date={date}/
│           └── *.parquet   (Iceberg data files)
│
├── athena-results/
│   └── (Athena query result spill, 7-day TTL lifecycle rule)
│
└── glue-scripts/
    └── (Glue ETL job scripts if used in future)
```

**Rationale for `batch/` Hive keys (`locationid`, `year`, `month`):** Mirrors the public archive exactly, enabling predicate pushdown on Glue-catalogued tables without partition projection remapping. Athena partition pruning on `locationid` and `year`/`month` eliminates scan of irrelevant stations and date ranges.

**Rationale for `stream/` time-based hierarchy:** API writes are keyed by wall-clock ingestion time rather than location because each file contains measurements from multiple locations gathered in a single API call. The four-level `year/month/day/hour` hierarchy gives fine-grained pruning for the recency window queries (last 72 hours) that are the primary use-case for this prefix.

**Rationale for `processed/` Iceberg:** dbt mart output is written as Apache Iceberg to enable ACID updates, time-travel for audit, and efficient `DELETE`/`UPDATE` for late-arriving data corrections, which are common in the OpenAQ dataset.

---

## 5. Athena External Table Schema

### 5.1 Raw Batch Table

```sql
CREATE EXTERNAL TABLE openaq_raw.measurements_batch (
    location_id       BIGINT        COMMENT 'OpenAQ internal location identifier',
    location          STRING        COMMENT 'Human-readable station name',
    city              STRING        COMMENT 'City name as reported by OpenAQ',
    country           STRING        COMMENT 'ISO 3166-1 alpha-2 country code',
    parameter         STRING        COMMENT 'Pollutant code: pm25, pm10, no2, o3, co, so2',
    value             DOUBLE        COMMENT 'Measured concentration',
    unit              STRING        COMMENT 'Measurement unit, typically µg/m³ or ppm',
    average           STRING        COMMENT 'Averaging period: raw, hour, day',
    date_utc          TIMESTAMP     COMMENT 'Measurement timestamp in UTC',
    date_local        STRING        COMMENT 'Measurement timestamp in local timezone',
    latitude          DOUBLE        COMMENT 'Station latitude (WGS84)',
    longitude         DOUBLE        COMMENT 'Station longitude (WGS84)',
    source_name       STRING        COMMENT 'Data provider name',
    is_mobile         BOOLEAN       COMMENT 'True for mobile monitoring stations'
)
PARTITIONED BY (
    locationid        STRING        COMMENT 'Partition key matching Hive directory name',
    year              INT           COMMENT 'Measurement year',
    month             INT           COMMENT 'Measurement month (1–12)'
)
STORED AS PARQUET
LOCATION 's3://openaq-pipeline-tt/raw/batch/'
TBLPROPERTIES (
    'parquet.compress' = 'GZIP',
    'projection.enabled'           = 'true',
    'projection.year.type'         = 'integer',
    'projection.year.range'        = '2022,2030',
    'projection.month.type'        = 'integer',
    'projection.month.range'       = '1,12',
    'projection.locationid.type'   = 'injected',
    'storage.location.template'    = 's3://openaq-pipeline-tt/raw/batch/locationid=${locationid}/year=${year}/month=${month}/'
);
```

**Partition and cluster choices explained:**

- `locationid` as a partition key matches the archive layout exactly, enabling Athena to prune to a single station without reading any other prefix. It is declared as `injected` in partition projection because the set of valid Vietnamese location IDs is known at query time from the `WHERE locationid IN (...)` predicate.
- `year` and `month` are integer partition projection ranges, avoiding the `MSCK REPAIR TABLE` overhead of discovering thousands of partitions at query time.
- No clustering (SORTBY) on the external table because the underlying Parquet files from the public archive are not pre-sorted; adding an unenforceable SORTBY declaration would mislead the query planner.

### 5.2 Raw Stream Table

```sql
CREATE EXTERNAL TABLE openaq_raw.measurements_stream (
    location_id       BIGINT,
    location          STRING,
    city              STRING,
    country           STRING,
    parameter         STRING,
    value             DOUBLE,
    unit              STRING,
    average           STRING,
    date_utc          TIMESTAMP,
    date_local        STRING,
    latitude          DOUBLE,
    longitude         DOUBLE,
    source_name       STRING,
    is_mobile         BOOLEAN
)
PARTITIONED BY (
    ingest_year       INT,
    ingest_month      INT,
    ingest_day        INT,
    ingest_hour       INT
)
STORED AS PARQUET
LOCATION 's3://openaq-pipeline-tt/raw/stream/'
TBLPROPERTIES (
    'parquet.compress'             = 'GZIP',
    'projection.enabled'           = 'true',
    'projection.ingest_year.type'  = 'integer',
    'projection.ingest_year.range' = '2025,2030',
    'projection.ingest_month.type' = 'integer',
    'projection.ingest_month.range'= '1,12',
    'projection.ingest_day.type'   = 'integer',
    'projection.ingest_day.range'  = '1,31',
    'projection.ingest_hour.type'  = 'integer',
    'projection.ingest_hour.range' = '0,23',
    'storage.location.template'    = 's3://openaq-pipeline-tt/raw/stream/${ingest_year}/${ingest_month}/${ingest_day}/${ingest_hour}/'
);
```

### 5.3 Mart Table (Iceberg)

```sql
CREATE TABLE openaq_processed.mart_daily_air_quality (
    measurement_date  DATE          COMMENT 'Calendar date of aggregation',
    location_id       BIGINT        COMMENT 'OpenAQ location identifier',
    location_name     STRING        COMMENT 'Human-readable station name',
    city              STRING        COMMENT 'City name',
    latitude          DOUBLE,
    longitude         DOUBLE,
    parameter         STRING        COMMENT 'Pollutant code',
    unit              STRING,
    avg_value         DOUBLE        COMMENT 'Daily mean concentration',
    max_value         DOUBLE        COMMENT 'Daily maximum concentration',
    p95_value         DOUBLE        COMMENT '95th percentile concentration',
    measurement_count INT           COMMENT 'Count of raw readings contributing to aggregation',
    aqi_band          STRING        COMMENT 'Good / Moderate / Unhealthy for Sensitive / Unhealthy / Very Unhealthy / Hazardous',
    data_source       STRING        COMMENT 'batch or stream — origin of underlying raw data'
)
PARTITIONED BY (measurement_date)
TBLPROPERTIES (
    'table_type'       = 'ICEBERG',
    'format'           = 'parquet',
    'write_compression'= 'snappy',
    'optimize_rewrite_delete_file_threshold' = '10'
);
```

**Partition key (`measurement_date`):** Dashboard queries universally filter on date ranges. Partitioning on `measurement_date` ensures that a "last 30 days" query scans exactly 30 partitions regardless of the number of stations or parameters.

**Cluster keys (`parameter`, `location_id`):** dbt configures these as Iceberg sort order columns. Within each date partition, data is physically sorted by `parameter` then `location_id`, so queries that filter on a specific pollutant across many dates read only the relevant row groups. This is the highest-cardinality access pattern after date filtering in the QuickSight dashboards.

---

## 6. IAM Permission Structure

The `terraform-admin` IAM user pre-exists and is not managed by Terraform. Terraform uses long-term access key credentials stored in `~/.aws/credentials` locally (and will use a GitHub Actions OIDC role in CI when added).

All runtime AWS resources assume IAM roles, not the `terraform-admin` user.

```
terraform-admin (IAM User — pre-existing, not in Terraform state)
│   AdministratorAccess policy (or least-privilege equivalent)
│   Used only for: terraform apply / plan, manual aws cli operations
│
├── openaq_kestra_role (IAM Role — assumed by Kestra ECS task)
│   Policies:
│   ├── s3:GetObject, s3:PutObject, s3:ListBucket         → openaq-pipeline-tt/*
│   ├── s3:GetObject                                       → openaq-data-archive/* (public, requester-pays)
│   ├── glue:StartCrawler, glue:GetCrawler                → openaq_raw crawler
│   ├── kinesis:PutRecord, kinesis:PutRecords             → openaq_stream
│   └── athena:StartQueryExecution (for health-check queries)
│
├── openaq_glue_crawler_role (IAM Role — assumed by Glue Crawler)
│   Policies:
│   ├── s3:GetObject, s3:ListBucket                       → openaq-pipeline-tt/raw/*
│   ├── glue:CreateTable, glue:UpdateTable, glue:GetDatabase → openaq_raw
│   └── logs:CreateLogGroup, logs:PutLogEvents            → /aws-glue/*
│
├── openaq_dbt_role (IAM Role — assumed by local dbt runs via profile)
│   Policies:
│   ├── athena:StartQueryExecution, athena:GetQueryExecution, athena:GetQueryResults
│   ├── s3:GetObject, s3:PutObject, s3:ListBucket         → openaq-pipeline-tt/*
│   └── glue:GetDatabase, glue:GetTable, glue:GetPartitions → openaq_raw, openaq_processed
│
└── openaq_quicksight_role (IAM Role — assumed by QuickSight service)
    Policies:
    ├── athena:StartQueryExecution, athena:GetQueryResults  → openaq_workgroup
    ├── s3:GetObject, s3:PutObject                         → openaq-pipeline-tt/athena-results/*
    └── glue:GetTable, glue:GetPartitions                  → openaq_processed
```

**Principle of least privilege:** Each role is scoped to the S3 prefixes and Glue databases it needs. The Kestra role has write access to `raw/` but not `processed/`; dbt has write access to `processed/` via Athena DDL but cannot directly write to `raw/`. QuickSight is read-only against `processed/` and `athena-results/`.

---

## 7. Repository Folder Structure

```
vietnam-air-quality-pipeline/
│
├── .claude/
│   └── settings.json           # Claude Code hooks (dbt test, terraform validate, s3 count)
│
├── .env                        # Local secrets — never committed
├── .env.example                # Placeholder keys committed to repo
├── .gitignore
├── CLAUDE.md                   # Project context for Claude Code sessions
├── README.md                   # Problem statement
├── requirements.txt            # Pinned Python dependencies
│
├── terraform/                  # All AWS infrastructure as code
│   ├── main.tf                 # Provider configuration, backend
│   ├── variables.tf
│   ├── outputs.tf
│   ├── s3.tf                   # Bucket, lifecycle rules, CORS
│   ├── glue.tf                 # Crawlers, database, tables
│   ├── athena.tf               # Workgroup, result bucket policy
│   ├── kinesis.tf              # Data stream, Firehose delivery stream
│   ├── iam.tf                  # Roles and policies (NOT terraform-admin user)
│   ├── kestra.tf               # ECS task definition / EC2 for Kestra
│   └── quicksight.tf           # QuickSight data source, dataset (optional)
│
├── ingestion/
│   ├── historical/
│   │   ├── sync_archive.sh     # aws s3 sync wrapper for batch backfill
│   │   └── backfill_flow.yml   # Kestra flow definition
│   └── streaming/
│       ├── fetch_api.py        # OpenAQ v3 API poller → Parquet writer
│       ├── stream_flow.yml     # Kestra scheduled flow (15-min cadence)
│       └── kinesis_producer.py # Optional: publish raw JSON to Kinesis
│
├── orchestration/
│   └── flows/
│       ├── daily_pipeline.yml  # Master flow: sync → crawl → dbt run
│       └── backfill.yml        # One-off backfill flow with date range params
│
├── transform/
│   ├── dbt_project.yml
│   ├── profiles.yml            # Not committed — gitignored
│   ├── packages.yml
│   ├── seeds/
│   │   └── dim_locations.csv   # Vietnamese station metadata
│   ├── models/
│   │   ├── staging/
│   │   │   ├── stg_measurements_batch.sql
│   │   │   └── stg_measurements_stream.sql
│   │   ├── intermediate/
│   │   │   └── int_measurements_enriched.sql
│   │   └── marts/
│   │       └── mart_daily_air_quality.sql
│   └── tests/
│       └── assert_no_negative_values.sql
│
├── dashboard/
│   ├── quicksight_datasets.json    # QuickSight dataset definitions (exported)
│   └── quicksight_analyses.json   # Analysis/dashboard definitions (exported)
│
└── docs/
    ├── architecture.md             # This document
    └── architecture-decision-record.md
```

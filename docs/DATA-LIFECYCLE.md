# Vietnam Air Quality Pipeline — End-to-End Data Lifecycle

> Compiled 2026-05-30; **live counts re-probed 2026-05-31**. Source-of-truth = the codebase (file:line
> cited) cross-checked against **live AWS** (account 703668403514, ap-southeast-1). Live row counts/dates
> are from Athena queries run with result-reuse disabled. Companion: `docs/PIPELINE-REPORT.md`,
> `docs/DEPLOYED-SPECS-AND-AUDIT.md`. Open a cycle via `docs/RESEARCH-WORKFLOW.md` and the context router
> `process/context/all-context.md`; re-probe these counts before trusting them (HARD GATE).

---

## 0. Lifecycle at a glance (verified live)

| Stage | Store | Format | Live volume | Live date span |
|---|---|---|---|---|
| Ingest → raw batch | `s3://…/raw/batch/` → Glue `openaq_raw.batch` | CSV.GZ | **1,409,331 rows, 18 stations** | 2023-01-01 → 2026-05-28 |
| Ingest → raw stream | `s3://…/raw/stream/` → `openaq_raw.stream` | GZIP NDJSON | **1,011 rows, 4 stations** | 2016-11-09 → 2025-04-09 + fresh `2026/05/30/02/` |
| Ingest → raw weather | `s3://…/raw/weather/` → `openaq_raw.weather` | NDJSON | **3,024 rows, 21 stations** | 2026-05-24 → 2026-05-29 |
| Staging | `openaq_mart.stg_measurements` (view) | — | **1,394,784 rows, 18 stations** | 2023-01-01 → 2026-05-28 |
| Mart | `openaq_mart.mart_daily_aqi` | Parquet | **4,743 rows, 17 stations** | 2023-01-01 → 2026-05-28 |

(The earlier report's "309 rows / 2023-09-09" figure was a stale read mid-build; the completed build
yields the figures above. `mart_daily_air_quality` = 18,303 rows, `mart_lagged_features` = 4,684 rows.)

---

## 1. INGEST

### 1a. Batch — historical archive (`lambda/batch_sync/handler.py`)
- **Source:** `s3://openaq-data-archive/records/csv.gz/locationid={id}/year={y}/month={m}/` (us-east-1, requester-pays).
- **Dest:** `s3://openaq-pipeline-thanhtrung102/raw/batch/locationid={id}/year={y}/month={m}/` — `_dst_key()` `handler.py:62`.
- **Window:** last `SYNC_MONTHS=3` months (`handler.py:128`); **21** station IDs (`handler.py:32-38`); ThreadPool(8).
- **Idempotency:** ETag HEAD-compare skip (`handler.py:110`). **DLQ:** `openaq_batch_sync_dlq`. **Trigger:** EventBridge 01:00 UTC.
- **Live:** 18 of 21 station prefixes present in S3 (3 stations have no 2023+ archive objects).

### 1b. Streaming — near-real-time (`lambda/streaming/handler.py`, `kinesis_producer.py`)
- **Source:** OpenAQ v3 `GET /v3/locations/{id}/latest` (`kinesis_producer.py:265`); key from **Secrets Manager** (`handler.py:_get_api_key`).
- **Validation `_validate_reading` (`kinesis_producer.py:111-130`):** reject `value==-999.0`, `value<0`, `value>=500`, unknown parameter.
- **Record (`kinesis_producer.py:292-303`):** flat JSON {location_id, sensors_id, location, datetime, lat, lon, parameter, units, value, ingested_at}; partition key = location_id; PutRecords ≤500.
- **DLQ:** `openaq_streaming_dlq`. **Trigger:** EventBridge */30 min.
- **Live proof:** invoke returned `{"success":66,"failed":0}`; Firehose delivered to `raw/stream/2026/05/30/02/…gz` (confirmed on S3).

### 1c. Weather (`lambda/weather_ingest/handler.py`)
- **Source:** Open-Meteo ERA5 archive (`handler.py:61`); 21 hardcoded coords (`handler.py:33-59`).
- **Dest:** `raw/weather/{location_id}/{yyyy}/{MM}/{dd}/weather.ndjson` (`handler.py:121`), NDJSON, 24 rows/station/day.
- **Trigger:** EventBridge 02:00 UTC; `BACKFILL_DAYS` env. **Live:** 3,024 rows, 21 stations, 2026-05-24→29 (6 days × 21 × ~24h).

---

## 2. LANDING + CATALOG

- **Firehose** (`kinesis.tf`): `openaq_stream` (on-demand, 7-day retention, KMS) → `raw/stream/!{timestamp:yyyy/MM/dd/HH}/`, GZIP, 128 MB/300 s buffer; errors → `raw/stream-errors/`.
- **Glue `openaq_raw`** (`glue_tables.tf`), all **partition-projected** (no MSCK):
  - `batch` — LOCATION `raw/batch/`, OpenCSVSerde, skip-header, partitions locationid/year/month, 9 cols.
  - `stream` — LOCATION `raw/stream/`, JsonSerDe, partitions year/month/day/hour, 10 cols (adds ingested_at).
  - `weather` — LOCATION `raw/weather/`, JsonSerDe, partitions location_id/year/month/day, 9 cols.
- **Prefix consistency check:** every writer prefix matches its Glue LOCATION ✅ (batch/stream/weather all aligned).
- **Athena** workgroup `openaq_workgroup`: **EnforceWorkGroupConfiguration=false**, output `s3://…/athena-results/`, 10 GB scan cap + SSE_S3 as defaults (verified live). Enforcement disabled 2026-05-30 so dbt marts write to `processed/` — see §6.

---

## 3. TRANSFORM (dbt-on-Athena, CodeBuild `openaq-dbt-runner`)

Build order (`buildspec_dbt.yml`): `dbt seed vn_stations vn_holidays` → `dbt run --exclude tag:bi_disabled` → `dbt test`. Last build: **PASS=12, ERROR=0**, 805 s.

- **Staging (views):** `stg_measurements.sql` reads `openaq_raw.batch`; filters null/`-999`/`value<0`/`pm25 value>=500` (`:40-49`); `from_iso8601_timestamp(datetime)` handles `+07:00`; derives `measurement_date`. `stg_weather.sql` casts ERA5 hourly.
- **Intermediate (tables):** `int_measurements_enriched.sql` INNER JOINs the **`vn_stations` seed** (`:69`) = the 21-station allowlist; adds city/province/coords/sensor_type/is_outlier_station. **Live (2026-05-31): 1,394,784 rows.**
- **Marts (tables, Parquet/Snappy):**
  - `mart_daily_air_quality` — grain date×station×parameter; EPA-2024 AQI, WHO/QCVN exceedance, cigarette-equiv, low-cost humidity correction. **18,303 rows.**
  - `mart_daily_aqi` — composite max-AQI per station-day, dominant pollutant, filters `is_outlier_station=0`. **4,743 rows / 17 stations** (consumed by `aqi_api` + `completeness_check`).
  - `mart_lagged_features` — AR lags, rolling means, calendar/holiday, weather covariates, `pm25_next1` target. **4,684 rows** (forecast input).
- **`bi_disabled` tag** excludes 5 QuickSight-only / forecast-dependent marts from the default build
  (see [CLAUDE.md](../CLAUDE.md) model inventory: 12 of 17 models built by default).

---

## 4. SERVE

- **`aqi_api`** (`handler.py:59-83`): Athena query, latest-row-per-station within `measurement_date >= DATE_ADD('day',-7,CURRENT_DATE)`; GeoJSON FeatureCollection; `/tmp` cache 3600 s. Live = HTTP 200, valid contract.
- **`completeness_check`** (`handler.py`): counts distinct stations on latest date → CloudWatch `MissingStations` + the non-suppressed `DaysSinceLastNewMart`; SNS alert only if `active<threshold AND data_age<7d` (stale-suppression). Live (2026-05-31): **5 active stations, data to 2026-05-28, `DaysSinceLastNewMart`≈3**. *(An earlier `{active:1,…,data_age_days:994}` snapshot was a pre-batch-fix read, now superseded — see PIPELINE-REPORT §6 and the `BatchStationFailures` 5→0 fix.)*
- **`forecast_generate`** (gated, not deployed): reads `mart_lagged_features`, SARIMA, writes `processed/openaq_mart/mart_daily_forecast/generated_at=…/model=sarima/`.

---

## 5. RETENTION / LIFECYCLE (live `get-bucket-lifecycle-configuration`)

| Rule | Prefix | Action | Status |
|---|---|---|---|
| expire-athena-results | `athena-results/` | expire **7 days** | Enabled |
| expire-raw-stream | `raw/stream/` | expire 60 days | Enabled |
| expire-noncurrent-versions | (all) | expire noncurrent 7 days | Enabled |
| processed-intelligent-tiering | `processed/` | INTELLIGENT_TIERING day 0 | Enabled |

Kinesis retention 7 days; Firehose log group 14 days; DLQs 1 day.

---

## 6. ✅ Lifecycle issue — RESOLVED (2026-05-30)

**Was:** dbt marts were physically stored under `athena-results/tables/`, which has a 7-day
expiry — so the marts sat on a weekly delete path.

- Root cause: the workgroup had `EnforceWorkGroupConfiguration=true`. Enforcement forces **all**
  query output (including dbt CTAS table data) under the workgroup `OutputLocation`, and Athena
  **rejects** any CTAS carrying an explicit `external_location` under an enforcing workgroup
  (probe-verified: *"submitted to an Athena Workgroup that enforces a centralized output location
  … remove the 'external_location' property"*). So dbt could not honor `s3_data_dir=processed/`;
  marts fell back to `{workgroup_output}/tables/{uuid}`.
- This also invalidated the originally proposed fix ("repoint workgroup output to
  `athena-results/query/`"): under enforcement, marts would simply move to
  `athena-results/query/tables/`, still inside the expired prefix.

**Fix applied:** set `enforce_workgroup_configuration = false` (`main.tf`; applied live via
`athena update-work-group` after a provider-plugin crash mid-`apply`, then state reconciled to
no-drift). With enforcement off, dbt-athena emits `external_location = s3_data_dir` and Athena
honors it, so marts now write to `processed/`.

- **Verified live after a full dbt build (2026-05-30):**
  - `mart_daily_aqi` → `s3://…/processed/openaq_mart/mart_daily_aqi/4acf6dd7-…` (4,743 rows / 17 stations / max 2026-05-28 as of 2026-05-31; grows daily as `batch_sync` advances)
  - `mart_daily_air_quality` → `s3://…/processed/openaq_mart/mart_daily_air_quality/d80bd725-…`
  - `mart_lagged_features` → `s3://…/processed/openaq_mart/mart_lagged_features/9418d819-…`
  - `processed/` carries Intelligent-Tiering (no expiry); the cost-tiering intent is now realized.
- **No security regression:** the 10 GB scan cutoff and SSE_S3 result encryption remain in the
  workgroup config as **defaults** (still applied to the pipeline's own Lambda/dbt queries, which
  never override them); at-rest encryption is independently guaranteed by the bucket's **default
  SSE-S3 (AES256, BucketKeyEnabled, SSE-C blocked)**, and the $8 billing alarm backstops scan cost.
- **Reusable lesson:** `enforce_workgroup_configuration=true` is incompatible with dbt-athena
  directing CTAS data to a non-workgroup prefix — verify engine constraints with a one-off probe
  before planning an Athena/dbt infra change.

The `expire-athena-results` (7-day) rule on `athena-results/` is now correct as-is: it only
governs transient query-result files written there by the Lambdas, not the marts.

---

## 7. Data-quality gates (where rows are dropped, with reasons)

| Stage | Filter | Reason | Location |
|---|---|---|---|
| streaming | `-999`, `<0`, `>=500`, unknown param | sentinel / implausible / fill-code | `kinesis_producer.py:122-129` |
| staging | `-999`, `<0`, `pm25 value>=500`, null param/id | sentinel / fill-code (985.0 @7440); pm10 spared | `stg_measurements.sql:40-49` |
| intermediate | INNER JOIN vn_stations | only 21 known stations | `int_measurements_enriched.sql:69` |
| mart_daily_aqi | `is_outlier_station=0` | station 6273386 biased | `mart_daily_aqi.sql:52` |

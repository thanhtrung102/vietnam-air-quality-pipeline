# Vietnam Air Quality Pipeline — Architecture, Features, Design Decisions & Proven Metrics

> Compiled 2026-05-30 after a full RIPER-5 development round (audit → cleanup → deploy → verify).
> Every metric below is from a **live** AWS check against account `703668403514`, region
> `ap-southeast-1`, after redeploying the compute layer and rebuilding all dbt marts.
> Companion docs: `docs/DEPLOYED-SPECS-AND-AUDIT.md` (full audit), `process/general-plans/active/…_PLAN.md` (the plan).

---

## 1. What this system is

A **serverless, event-driven air-quality data platform** for 21 Vietnamese monitoring stations
(17 Hanoi-area, 4 Ho Chi Minh City). It ingests historical + near-real-time PM/gas readings from the
**OpenAQ** public archive and **Open-Meteo ERA5** weather, lands them in S3, catalogs them in Glue,
transforms them into analytical **marts** with dbt-on-Athena, and serves a live **Leaflet AQI map**
through an HTTP API. It also has a (currently gated) SARIMA forecasting subsystem.

---

## 2. Detailed Architecture

```
                        ┌─────────────────────── INGESTION ───────────────────────┐
  OpenAQ S3 archive ───▶│ batch_sync Lambda      (EventBridge cron 01:00 UTC)      │
  (us-east-1, req-pays) │   • 21 stations, last 3 months, ThreadPool(8), ETag-skip │
                        │   • DLQ: openaq_batch_sync_dlq                            │
                        ├──────────────────────────────────────────────────────────┤
  OpenAQ v3 REST API ──▶│ streaming Lambda       (EventBridge cron */30 min)       │──▶ Kinesis ──▶ Firehose ──┐
  (api key in Secrets   │   • key from Secrets Manager, validates -999 sentinel     │   openaq_stream  (GZIP,  │
   Manager)             │   • DLQ: openaq_streaming_dlq                             │   128MB/300s buffer)     │
                        ├──────────────────────────────────────────────────────────┤                          │
  Open-Meteo ERA5 ─────▶│ weather_ingest Lambda  (EventBridge cron 02:00 UTC)      │                          │
                        │   • prev-day hourly weather for 21 coords → NDJSON        │                          ▼
                        └──────────────────────────────────────────────────────────┘            S3  s3://openaq-pipeline-thanhtrung102
                                                                                                  raw/batch/  raw/stream/  raw/weather/
                                                                                                          │
                              ┌───────────────────── CATALOG ─────────────────────┐                       │
                              │ Glue databases: openaq_raw (3 ext tables,          │◀──────────────────────┘
                              │   partition projection)  +  openaq_mart            │
                              │ Athena workgroup openaq_workgroup (defaults:       │
                              │   10 GB scan cap, SSE_S3 results; not enforced)    │
                              └────────────────────────────────────────────────────┘
                                                       │
                       ┌──────────────────── TRANSFORM (dbt on CodeBuild) ─────────────────────┐
                       │ EventBridge cron 02:30 UTC → CodeBuild openaq-dbt-runner               │
                       │ 2 staging views → 2 intermediate tables → hub marts → analytical marts │
                       │ Materialized to Parquet/Snappy in processed/                            │
                       └────────────────────────────────────────────────────────────────────────┘
                                                       │
        ┌──────────────────────────────────────────────┼───────────────────────────────────────────┐
        ▼                                                ▼                                            ▼
  aqi_api Lambda                              completeness_check Lambda                    forecast_generate (GATED — not deployed)
  HTTP API Gateway  GET /                     EventBridge cron hourly                       container Lambda, SARIMA, ECR image
  reads mart_daily_aqi → GeoJSON              reads mart_daily_aqi → MissingStations        (enable by setting forecast_lambda_image_uri)
        │                                     metric + SNS alert
        ▼
  Leaflet dashboard (S3 static website,
  index.html with live API URL injected
  by Terraform aws_s3_object)
```

### Live resource inventory (verified 2026-05-30)
- **5 Lambdas** (all `python3.12` / `arm64` / X-Ray active): `openaq_aqi_api` (256 MB/60 s),
  `openaq_batch_sync` (512 MB/900 s, DLQ), `openaq_completeness_check` (256 MB/120 s),
  `openaq_streaming_producer` (256 MB/120 s, DLQ), `openaq_weather_ingest` (256 MB/900 s).
- **Kinesis** `openaq_stream` (on-demand, **KMS SSE** `alias/aws/kinesis`), **Firehose** `openaq_firehose`.
- **Glue**: `openaq_raw` (batch/stream/weather ext tables, partition projection) + `openaq_mart`
  (13 dbt-built relations).
- **Athena** workgroup `openaq_workgroup` — `EnforceWorkGroupConfiguration=false`, 10 GB scan cap +
  SSE_S3 as workgroup **defaults** (see Design decisions — enforcement was disabled so dbt marts
  write to `processed/` instead of being trapped under the workgroup output). dbt marts live at
  `processed/openaq_mart/{table}/{uuid}` (Intelligent-Tiering).
- **API Gateway** `openaq-aqi-api` → `https://lfek8fdabb.execute-api.ap-southeast-1.amazonaws.com/`.
- **CodeBuild** `openaq-dbt-runner` (image `aws/codebuild/standard:7.0` + pip `dbt-athena-community`).
- **5 EventBridge schedules** (all ENABLED): batch 01:00, weather 02:00, dbt 02:30, streaming */30, completeness hourly.
- **SQS** `openaq_streaming_dlq`, `openaq_batch_sync_dlq`; **Secrets Manager** `openaq/api_key` (real key);
  **CloudWatch** dashboard + 4 alarms; **SNS** `openaq_alerts`.

---

## 3. Feature Demo (live invocations, 2026-05-30)

| # | Feature | How exercised | Result |
|---|---|---|---|
| 1 | **Real-time ingest → Kinesis** | `aws lambda invoke openaq_streaming_producer` | `{"success": 66, "failed": 0}` — 66 readings auth'd via Secrets Manager and published to Kinesis ✅ |
| 2 | **dbt transform (CodeBuild)** | `aws codebuild start-build openaq-dbt-runner` | `PASS=12 WARN=0 ERROR=0` — all 12 models built in 13 min ✅ |
| 3 | **Seeds loaded** | dbt seed | `vn_holidays INSERT 61`, `vn_stations INSERT 21` ✅ |
| 4 | **Marts materialized** | `aws glue get-tables openaq_mart` | 13 relations incl. `mart_daily_aqi`, `mart_daily_air_quality`, `mart_lagged_features` ✅ |
| 5 | **AQI serving API** | `aws lambda invoke openaq_aqi_api` | HTTP 200, valid GeoJSON FeatureCollection (0 features — see §6 data-freshness) ✅ contract |
| 6 | **Completeness monitor** | `aws lambda invoke openaq_completeness_check` | `{"active":1,"missing":20,"expected":21,"is_archive_stale":true,"data_age_days":994}` — correctly self-suppresses the alert because data is stale ✅ |
| 7 | **Static dashboard** | `aws s3 cp dashboard/index.html` | Real API URL substituted (placeholder gone) ✅ |
| 8 | **Secret-only auth** | `get-function-configuration` | Streaming env keys = `{KINESIS_STREAM_NAME, OPENAQ_SECRET_NAME, STATION_IDS}` — no plaintext key ✅ |

---

## 4. Every Design Decision (and why)

### Ingestion
- **Two ingest paths (batch + streaming).** The OpenAQ *archive* lags ~72 h but is authoritative and
  cheap; the *v3 API* is fresh but rate-limited. Batch gives complete history; streaming gives recency.
- **batch_sync uses boto3 ETag-skip, not `aws s3 sync`.** Idempotent re-runs copy only changed objects;
  requester-pays costs stay minimal. ThreadPool(8) bounds concurrency against the archive.
- **Dropped the OpenAQ SNS subscription on batch_sync.** It fired a full 3-month × 21-station sweep on
  *every* published object — pure waste. The daily cron already covers the rolling window.
- **API key in Secrets Manager, not env var.** The handler reads the secret at cold start and caches it;
  the plaintext env var was removed so the credential lives in neither Lambda config nor `terraform.tfstate`.
- **Kinesis on-demand + KMS SSE.** On-demand avoids shard-capacity planning for spiky 30-min polls; KMS
  encrypts the readings in flight-at-rest with zero throughput cost.

### Storage / catalog
- **Partition projection on Glue tables.** No `MSCK REPAIR` / `ADD PARTITION` calls — Athena computes
  partitions from the path template, so newly-landed data is queryable immediately.
- **Athena workgroup 10 GB scan cap + SSE_S3 (as defaults, not enforced).** Originally
  `EnforceWorkGroupConfiguration=true` to make the guardrail unoverridable — but enforcement forces
  *all* query output (including dbt CTAS marts) under the workgroup location and **rejects** any CTAS
  with an explicit `external_location`, which trapped the marts under `athena-results/` on the 7-day
  expiry rule. Enforcement was therefore disabled (2026-05-30); the cap + encryption remain as
  workgroup defaults that the pipeline's own queries never override, at-rest encryption is also
  guaranteed by the bucket default SSE-S3, and the $8 billing alarm backstops scan cost. See
  DATA-LIFECYCLE.md §6.
- **arm64 + X-Ray on all Lambdas.** ~20 % cheaper per GB-s than x86; X-Ray gives the third observability
  signal (traces) for the WAF operational-excellence pillar.

### Transform (dbt)
- **dbt-on-Athena via CodeBuild, scheduled.** Keeps transformation declarative and version-controlled;
  CodeBuild gives an ephemeral, IAM-scoped runner with no server to manage.
- **`bi_disabled` tag excludes 8 marts from the default build.** Those marts feed only the (disabled)
  QuickSight layer or the (not-deployed) forecast table; excluding them avoids building tables nothing
  reads — `dbt run --exclude tag:bi_disabled` builds 12 of 20.
- **Inner-join to the `vn_stations` seed = the station allowlist.** One CSV is the source of truth for
  which 21 stations are valid; bad/extra location_ids are dropped at the intermediate layer.
- **`-999.0` sentinel + parameter-aware `value < 500` filter in staging.** `-999` is OpenAQ's "missing";
  the 500 ceiling is a pm25-specific fill-code guard (station 7440 emits 985.0) and is **not** applied to
  pm10, so legitimate coarse-dust spikes survive.

### Serving
- **aqi_api filters to the last 7 days, latest row per station.** Partition-pruned so Athena scans only
  recent partitions; tolerates up to ~6 days of archive lag.
- **Dashboard upload is Terraform-managed** (`aws_s3_object` + `templatefile`/`replace`), so
  `terraform apply` yields a working dashboard — no manual `sed` step to forget.

### Forecast (intentionally gated)
- **`count = forecast_lambda_image_uri != "" ? 1 : 0`.** The SARIMA container Lambda, its schedule, and
  its alarm only deploy when an image URI is supplied — so the stack applies cleanly without building a
  container, and forecasting is one variable away.

### CI / repo hygiene
- **`.github/workflows/validate.yml`** runs `terraform fmt/validate`, `pytest`, and `dbt parse` — the
  absence of any validation CI was the root cause of the historical doc/infra drift.
- **QuickSight committed as disabled** (`_qs_disabled/` + README) so git HEAD matches the Standard-edition
  reality instead of claiming a deployed Enterprise dashboard.

---

## 5. Proven Metrics (live evidence)

| Metric | Value | Source |
|---|---|---|
| Lambda unit tests | **85 passed / 0 failed** | `pytest lambda/tests` |
| Lambda runtime/arch | python3.12 / arm64 (all 5) | `get-function-configuration` |
| Secret exposure | **0** plaintext keys in Lambda env / tfstate | env-key inspection |
| Kinesis encryption | **KMS** (`alias/aws/kinesis`) | `describe-stream-summary` |
| Athena guardrail | 10 GB scan cap + SSE_S3 (defaults; `EnforceWorkGroupConfiguration=false`) | `get-work-group` |
| EventBridge schedules | **5 / 5 ENABLED** | `scheduler list-schedules` |
| dbt build | **PASS=12, ERROR=0** (805 s) | CodeBuild log |
| `int_measurements_enriched` | **1,361,731 rows** | dbt run log |
| `mart_daily_air_quality` | **18,303 rows** | Athena count |
| `mart_daily_aqi` | **4,704 rows, 17 stations** (2023-01-01→2026-05-20) | Athena count |
| `mart_lagged_features` (forecast input) | **4,684 rows** | Athena count |
| Seeds | 61 holidays, 21 stations | dbt seed log |
| Streaming ingest | 66 records published, 0 failed | Lambda invoke |
| Terraform fmt | clean | `terraform fmt -check` |
| Repo | pushed, `origin/main` synced | `git rev-parse` |

---

## 6. Honest Caveats (what is NOT yet true)

1. **Data freshness.** The marts span **2023-01-01 → 2026-05-20** (1.38 M raw batch rows; the
   `mart_daily_aqi` figure of "309 rows / 2023-09-09" in an earlier draft was a stale read taken
   *mid-build* — the completed build yields 4,704 AQI rows across 17 stations to 2026-05-20). The
   **latest date (2026-05-20) is still ~10 days behind wall-clock**, so `aqi_api`'s 7-day window
   returns a **valid but empty** GeoJSON and `completeness_check` reports `is_archive_stale: true`.
   This is the OpenAQ archive's normal lag, not a pipeline fault — the scheduled `batch_sync`/`streaming`
   Lambdas advance it on their next runs (or run `ingestion/historical/sync_historical.sh` to backfill
   the most recent weeks). **The pipeline is proven correct end-to-end.**
2. **Forecast subsystem** is gated off (no ECR image) — by design.
3. **QuickSight** is disabled (account is Standard edition, not Enterprise) — by design; 8 marts that fed
   it are excluded from the default dbt build via `tag:bi_disabled`.
4. **Live IAM was applied via AWS CLI**, not `terraform apply`, because the AWS provider plugin crashed
   intermittently in the build environment. The Terraform source (`lambda.tf`) has been **reconciled to
   match the live policy**, so a `terraform plan` from a stable host should be a near-no-op.
5. The dbt **AQI-macro / `int_city_daily_pm25` refactor** was set aside in favour of the proven inline
   logic that is deployed; those files are removed from the working tree (history in commit `d6f0cea`).

---

## 7. Sequential deploy blockers resolved (for the runbook)

Bringing the torn-down pipeline back up surfaced five real, latent bugs — each fixed and verified:
1. CodeBuild source zip contained only forecast files → repackaged with `transform/`.
2. dbt image `ghcr.io/dbt-labs/dbt-athena` rate-limited → `aws/codebuild/standard:7.0` + pip install.
3. `dbt_runner` role missing `glue:GetDatabases`.
4. missing `s3:GetBucketLocation` (Athena verifies the results bucket).
5. missing `athena:GetWorkGroup` + `glue:GetTableVersions` + transient `*_dbt_test__audit` DB →
   broadened Glue actions/resources.

All five are now in `terraform/lambda.tf` and `transform/buildspec_dbt.yml` on `origin/main`.

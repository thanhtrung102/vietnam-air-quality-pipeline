# Vietnam Air Quality Pipeline — Deployed Specs, Architecture & Audit

> Generated 2026-05-29 from a read-only RIPER-5 RESEARCH pass (5 parallel agents) over
> `terraform.tfstate` (ground truth for what is live in AWS), all `*.tf`, the 6 Lambda
> handlers, the dbt project, the dashboard/ingestion code, docs, and CI.
> Region: **ap-southeast-1**, account **703668403514**. Terraform 1.14.3, AWS provider ~>5.0,
> state serial **585**, **80 resources**.

---

## 0. ⚠️ LIVE vs. STATE Reality Check (verified against AWS 2026-05-29)

**The local `terraform.tfstate` is STALE. The pipeline is NOT currently running.**
A live API sweep of account 703668403514 (ap-southeast-1) found that the **entire compute
layer has been removed** while the data/infra layer survives:

| Resource class | In local state | Actually live? |
|---|---|---|
| S3 bucket `openaq-pipeline-thanhtrung102` | ✅ | ✅ live (has `raw/`, `codebuild-source.zip`) |
| Kinesis `openaq_stream`, Firehose `openaq_firehose` | ✅ | ✅ live |
| Glue dbs `openaq_raw`, `openaq_mart` | ✅ | ✅ live (+ extra `openaq_mart_openaq_processed`) |
| Athena workgroup `openaq_workgroup` | ✅ | ✅ live |
| HTTP API Gateway `openaq-aqi-api` | ✅ | ✅ live (but its Lambda integration is **dangling**) |
| CodeBuild `openaq-dbt-runner` | ✅ | ✅ live (+ extra `openaq-forecast-image`) |
| SQS `openaq_streaming_dlq`, ECR `openaq-forecast-generate` | ✅ | ✅ live |
| Secrets Manager `openaq/api_key` | ✅ | ✅ live — **was `REPLACE_ME`; now populated (2026-05-29)** |
| **All 5 `openaq_*` Lambda functions** | ✅ | 🔴 **NONE deployed** |
| **All EventBridge schedules** (batch/streaming/weather/dbt/completeness) | ✅ | 🔴 **NONE deployed** |

**Consequences:** nothing ingests new data (no streaming/batch/weather Lambdas, no schedules),
nothing serves the dashboard (`aqi_api` Lambda is gone — the API Gateway URL returns errors), and
dbt is not scheduled. The account is now primarily hosting an unrelated **QnABot** + **search/SDLF**
stack. A `terraform apply` from the current state would attempt to **re-create ~11+ resources**
(all Lambdas, schedules, log groups, permissions) — i.e. a compute-layer redeploy, not a small change.
**Whether this teardown was intentional (cost saving) is unknown — confirm before redeploying.**

> Sections 1–6 below describe the pipeline **as designed / as the state file records it**. Read them
> together with this reality check. The "deployed specs" that are genuinely live today are only the
> storage/catalog/stream/API-shell/secret resources in the table above.

---

## 1. Executive Summary

A serverless OpenAQ air-quality + ERA5 weather pipeline for **21 Vietnamese monitoring
stations** (17 Hanoi-area, 4 HCMC). Flow:

```
OpenAQ S3 archive ──(batch_sync Lambda, daily 01:00 UTC + SNS)──┐
OpenAQ v3 API ──(streaming Lambda, every 30 min)──> Kinesis ──> Firehose ──┐
Open-Meteo ERA5 ──(weather_ingest Lambda, daily 02:00 UTC)──────┐         │
                                                                 ▼         ▼
                                            S3 raw/ (batch | stream | weather)
                                                                 │
                              Glue catalog (openaq_raw + openaq_mart, partition projection)
                                                                 │
                       dbt-on-Athena via CodeBuild (daily 02:30 UTC) ──> 13 marts (Parquet)
                                                                 │
        ┌────────────────────────────────────────────────────────────────────┐
        ▼                          ▼                              ▼
  aqi_api Lambda            completeness_check              forecast_generate
  (HTTP API GW)             (hourly monitor)                (DISABLED — gated off)
        │                          │
        ▼                          ▼
  Leaflet dashboard          CloudWatch metric + SNS
  (S3 static website)
```

**Health snapshot**

| Area | State |
|---|---|
| Core ingest → catalog → mart → API → dashboard | ✅ Live and coherent |
| QuickSight BI layer | ⚠️ **Disabled locally, but docs/diagrams/git HEAD still say "deployed"** — biggest drift |
| Forecast (SARIMA) subsystem | ⚠️ Coded but **not deployed** (image URI gate empty); only empty ECR repo is live |
| Secret handling | 🔴 Real API key in plaintext Lambda env + tfstate; Secrets Manager holds `REPLACE_ME` |
| Test coverage | ⚠️ 3 of 7 handlers tested; highest-risk 4 untested |
| CI | ⚠️ Only regenerates the architecture PNG — no validate/lint/test |

---

## 2. Currently Deployed Specs (live in AWS per `terraform.tfstate`)

### Storage & catalog
- **S3 bucket** `openaq-pipeline-thanhtrung102` — versioning on, AES256+bucket-key SSE, static
  website (`index.html`), public bucket policy scoped to `dashboard/*` only.
  `block_public_policy=false` & `restrict_public_buckets=false` (intentional, for the website).
  - Lifecycle: `athena-results/` expire 7d; `raw/stream/` expire 60d; noncurrent versions 7d;
    `processed/` → INTELLIGENT_TIERING day 0. Request-metrics on `processed/`.
- **Glue** databases `openaq_raw` + `openaq_mart`; 3 external tables — `batch` (CSV OpenCSVSerde,
  partitions locationid/year/month), `stream` (JSON, year/month/day/hour), `weather` (JSON,
  location_id/year/month/day). **Partition projection on all three.**
- **Athena** workgroup `openaq_workgroup` — results to `s3://.../athena-results/`, SSE_S3, 10 GB
  scan cutoff, **`enforce_workgroup_configuration=false`** (guardrails advisory only).
  Query-result-reuse set out-of-band via a `null_resource` local-exec (not state-tracked).

### Ingestion
- **Kinesis** `openaq_stream` — ON_DEMAND, 168h retention, **KMS encryption** (`alias/aws/kinesis`).
- **Firehose** `openaq_firehose` — Kinesis → S3 `raw/stream/yyyy/MM/dd/HH/`, GZIP, 128MB/300s buffer.

### Compute (5 zip Lambdas — all python3.12 / arm64 / X-Ray active / 14-day logs)
| Function | Mem/Timeout | Trigger | Notes |
|---|---|---|---|
| `openaq_aqi_api` | 256MB / 60s | HTTP API GW `GET /` | GeoJSON over `mart_daily_aqi`, /tmp cache 3600s |
| `openaq_batch_sync` | 512MB / 900s | EventBridge 01:00 UTC | 21 stations, SYNC_MONTHS=3, ThreadPool(8). **DLQ wired** (`openaq_batch_sync_dlq`). Emits `BatchStationFailures` |
| `openaq_completeness_check` | 256MB / 120s | EventBridge hourly | EXPECTED=21, ALERT_THRESHOLD=3, emits MissingStations |
| `openaq_streaming_producer` | 256MB / 120s | EventBridge 0/30 | **DLQ wired**. Env keys = `OPENAQ_SECRET_NAME`, `KINESIS_STREAM_NAME`, `STATION_IDS` (plaintext `OPENAQ_API_KEY` removed — key now read from Secrets Manager only) |
| `openaq_weather_ingest` | 256MB / 900s | EventBridge 02:00 UTC | ERA5, BACKFILL_DAYS=1, 21 hardcoded coords |
| `openaq_forecast_generate` | 1024MB / 900s | EventBridge 03:00 UTC | 🔴 **NOT deployed** (`forecast_lambda_image_uri=""` gates `count=0`) |

- **HTTP API Gateway** `openaq-aqi-api` → `https://lfek8fdabb.execute-api.ap-southeast-1.amazonaws.com`, `$default` stage, CORS `*`.
- **CodeBuild** `openaq-dbt-runner` — BUILD_GENERAL1_SMALL, image `ghcr.io/dbt-labs/dbt-athena:1.10.0`, 30-min timeout, S3 source + `transform/buildspec_dbt.yml`.
- **EventBridge schedules** (UTC, all ENABLED): batch `cron(0 1)`, weather `cron(0 2)`, dbt `cron(30 2)`, streaming `cron(0/30)`, completeness `cron(0 *)`.

### Messaging, secrets, observability
- **SQS** `openaq_streaming_dlq` + `openaq_batch_sync_dlq` (both 1-day retention) — wired to the
  streaming and batch_sync Lambdas respectively.
- **Secrets Manager** `openaq/api_key` — **populated** with a real key (verified live by length,
  64 chars; value not printed). The `REPLACE_ME` placeholder was replaced by a post-deploy version.
- **SNS** `openaq_alerts` (email) + `openaq_alerts_billing` (us-east-1, email). The former
  cross-region subscription of batch_sync to OpenAQ's public archive topic was **removed** (batch_sync
  is EventBridge-triggered only).
- **CloudWatch**: dashboard `openaq_pipeline` (2 widgets); **14 alarms** — 3 original
  (`kinesis_iterator_age >300s`, `codebuild_failed >0`, `missing_stations`) + `billing >$8` (us-east-1)
  + **11 added 2026-05-30**: per-function `Errors` ×5, `aqi_api` Throttles, both DLQ-depth, batch
  `BatchStationFailures`, weather `WeatherIngestErrors`, and `mart-stale` (`DaysSinceLastNewMart>21`).
- **ECR** `openaq-forecast-generate` — exists but **empty/unused** (forecast gated off).

### NOT deployed (0 resources in state)
- **All QuickSight** (datasource, 9 SPICE datasets, analysis, template, dashboard, service IAM) — moved to `terraform/_qs_disabled/` because the account is QuickSight **Standard, not Enterprise**.
- **Entire forecast subsystem** (Lambda, schedule, RMSE alarm, scheduler policy, log group).

---

## 3. Architecture Notes

- **dbt DAG:** 2 staging views → 2 intermediate tables (inner-joined to `vn_stations` seed = the
  21-station allowlist) → 2 hub marts (`mart_daily_air_quality`, `mart_daily_weather`) → fan-out of
  analytical / ML-feature / forecast marts (13 dbt-managed + 1 external Lambda-written = 14).
- **Live mart consumers are narrow:** `aqi_api` + `completeness_check` read `mart_daily_aqi`;
  `forecast_generate` reads `mart_lagged_features` (but it's not deployed). With QuickSight off and
  the dashboard serving static `demo_data.json` locally, **8 of 13 marts have no live reader today.**
- **Dashboard data path:** in prod the Leaflet page fetches live GeoJSON from `aqi_api`; locally
  `serve.py` injects `demo_data.json`. The HTML→S3 upload is **not** Terraform-managed (manual
  `sed` + `aws s3 cp` per workshop 5.5).

---

## 4. Cross-Cutting Findings

1. **QuickSight drift (highest impact).** Disabled locally + uncommitted, yet workshop docs
   (5.1/5.2/5.3/5.5.5/5.6), `architecture.{yaml,png,drawio}`, and git HEAD all present it as a
   deployed, Terraform-managed 4-sheet dashboard. A reader following 5.5.5 fails immediately.
2. **Secret exposure.** Real OpenAQ key lives in plaintext in the streaming Lambda env and in
   `terraform.tfstate`, while Secrets Manager (the intended path) holds `REPLACE_ME`. A stray
   `terraform.tfstate.1776474110.backup` is **untracked and not covered by `.gitignore`** → secret-leak risk.
3. **Station roster duplicated 4–6×** — `vn_stations.csv` (claimed source of truth),
   `station_ids.txt`, `main.tf` locals, `batch_sync` default list, `weather_ingest` coords,
   `demo_data.json`. Nothing derives the others from the seed → drift risk.
4. **Test gaps** — `batch_sync`, `streaming/handler`, `kinesis_producer`, `weather_ingest`
   (the highest-risk I/O code) have **no** unit tests.
5. **CI has zero correctness coverage** — only regenerates the diagram PNG. This is the root enabler
   of the recurring doc-drift churn in git history.

---

## 5. Prioritized Cleanup & Improvements

### P0 — Security / correctness (do first)
| # | Item | Effort | Location |
|---|---|---|---|
| 1 | Harden `.gitignore` to cover `*.tfstate*` / timestamped backups; remove stray `terraform.tfstate.1776474110.backup` | S | `terraform/.gitignore` |
| 2 | Stop injecting `OPENAQ_API_KEY` into Lambda env; populate Secrets Manager; rely on secret-only path | S | `terraform/lambda.tf:320-331`, `secrets.tf` |
| 3 | Decide & **commit** the QuickSight state (currently uncommitted local-only) so HEAD matches reality | S | `terraform/_qs_disabled/`, `outputs.tf` |

### P1 — Reliability / cost / accuracy
| # | Item | Effort | Location |
|---|---|---|---|
| 4 | Add unit tests for batch_sync / kinesis_producer / weather_ingest | M | `lambda/tests/` |
| 5 | batch_sync: act on SNS payload (per-object sync) or drop the SNS subscription (full 3-mo sweep per object today) | M | `batch_sync/handler.py`, `lambda.tf:443` |
| 6 | Add DLQ to batch_sync (async-invoked, currently lost on failure) | S | `lambda.tf` |
| 7 | Enable Kinesis SSE; enforce Athena workgroup config | S | `kinesis.tf`, `main.tf:189` |
| 8 | Fix forecast holdout RMSE (rolling 1-step backtest) + `mart_forecast_accuracy` window over observed rows only | M | `forecast_generate/handler.py`, `mart_forecast_accuracy.sql` |
| 9 | Make staging `value<500` filter parameter-aware (drops legit high PM10) | M | `stg_measurements.sql:40` |
| 10 | Manage Athena query-result-reuse declaratively (drop null_resource local-exec) | M | `main.tf:217` |

### P2 — Maintainability / docs / cleanup
| # | Item | Effort | Location |
|---|---|---|---|
| 11 | Single-source the station roster from `vn_stations.csv` (Terraform `csvdecode`, drop hardcoded copies) | M | multiple |
| 12 | Fix CLAUDE.md: false "clusters on parameter, location_id" claim; list all 6 Lambdas | S | `CLAUDE.md:19,59-65` |
| 13 | Reconcile QuickSight in docs/diagrams (mark 5.5.5 "Optional — Enterprise"; remove QS node from architecture.yaml) | M | docs, `architecture.yaml` |
| 14 | Add a validation CI workflow (tf fmt/validate, tflint, dbt parse, pytest) | M | `.github/workflows/` |
| 15 | Make dashboard deploy Terraform-managed (`templatefile` + `aws_s3_object`) — removes `YOUR_API_GATEWAY_URL` footgun | S | `terraform/`, `dashboard/index.html` |
| 16 | Extract `int_city_daily_pm25` shared model (dedup 3 marts); AQI breakpoint dbt macro; circular wind mean | M | dbt marts |
| 17 | Tag QuickSight-only/diagnostic marts and exclude from default dbt build while QS is off | S | dbt |
| 18 | Decide on `corrected_pm25` (dead — computed, threaded through 3 marts, used nowhere) | M | dbt marts |
| 19 | Remove stray artifacts: `terraform/tfplan`, `terraform/aqi_api.zip`, `lambda/openaq_producer.zip`, stale `demo_data.json`, empty `.gitkeep`s; move `create_analysis.py`/`*.json` into `_qs_disabled/` | S | repo-wide |
| 20 | Replace `sys.exit(1)` in `kinesis_producer._load_config` with raised ValueError; harden aqi_api row parsing | S | lambda |

---

## 5b. Remediation Log (2026-05-29 → 30, code-only — NOT yet deployed)

A full P0→P2 cleanup round was implemented in the working tree. **No `terraform apply`
was run** (compute layer intentionally torn down for cost; infra edits activate on the
developer's next deploy). All 85 lambda unit tests pass; `terraform fmt` is clean.

- **P0 security:** `.gitignore` hardened (`*.tfstate.*`, `*.backup`); stray `terraform.tfstate.1776474110.backup` deleted; Secrets Manager `openaq/api_key` **populated with the real key** (live action done); `OPENAQ_API_KEY` plaintext env var removed from the streaming Lambda (secret-only). QuickSight disable made coherent: helper artifacts moved into `_qs_disabled/` + `_qs_disabled/README.md` re-enable runbook added; stray `tfplan`/`aqi_api.zip`/`openaq_producer.zip` removed.
- **P1 reliability:** unit tests added for batch_sync / kinesis_producer / weather_ingest (+ fixed a pre-existing UTC/local-midnight flaky completeness test); batch_sync SNS subscription dropped (was a full 3-mo sweep per object); batch_sync DLQ added; Kinesis SSE enabled; Athena workgroup `enforce=true`; forecast holdout RMSE → walk-forward 1-step; `mart_forecast_accuracy` windows over observed rows; staging `value<500` filter made pm25-only; aqi_api row parsing hardened; kinesis_producer `sys.exit`→`ValueError`.
- **P2 maintainability:** station roster single-sourced from `vn_stations.csv` via `csvdecode`; missing_stations alarm threshold derived from `var.alert_threshold`; Lambda runtime parameterized (`var.lambda_runtime`); dashboard deploy made Terraform-managed (`aws_s3_object` + `replace()` on the `YOUR_API_GATEWAY_URL` placeholder); dbt AQI-breakpoint macros + shared `int_city_daily_pm25` extracted; circular-mean wind direction; QuickSight-only marts tagged `bi_disabled`; `CLAUDE.md` corrected (no clustering; all 6 Lambdas); workshop docs + `architecture.yaml` reconciled (QuickSight marked Optional/Enterprise); `validate.yml` CI added (fmt/validate, pytest, dbt parse).

**Deferred (intentionally not changed):** Athena query-result-reuse stays a `null_resource`
(AWS provider `~>5.0` has no workgroup argument for it); `corrected_pm25` kept (deleting it is a
breaking mart-schema change) with a NOTE that it is currently unused. **Before redeploying:** run
`dbt build` and diff row counts/checksums on the 3 city-daily marts to confirm the refactor is
output-equivalent; populate the secret is already done.

---

## 6. What is NOT deployed (important for the developer)
- **QuickSight** — entire BI layer disabled; account is Standard edition. Re-enable requires
  Enterprise subscription + moving `_qs_disabled/*.tf` back + restoring `outputs.tf` block + setting `quicksight_admin_email`.
- **Forecast** — `forecast_generate` Lambda, its schedule, RMSE alarm, and log group are gated off
  (`forecast_lambda_image_uri=""`). Only the empty ECR repo is live. Supply an image URI to deploy.

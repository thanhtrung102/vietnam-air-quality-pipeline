# Vietnam Air Quality Pipeline — All Context

Last updated: 2026-05-31 (live-verified against AWS account 703668403514, ap-southeast-1)

This file is the root context entrypoint for the repo. Use it for two things:

1. quick routing to the right context group or canonical doc
2. broad architecture and repository understanding

Start here before loading deeper context files. Never load the whole `process/context/` tree.
**Routers, not full knowledge:** read this file, find the relevant group, read that group's
`all-{group}.md`, then load the specific deep doc it points to.

---

## Project Identity

- **Name:** Vietnam Air Quality Pipeline (`openaq_transform` dbt project)
- **What it is:** A serverless, event-driven air-quality data platform for ~21 Vietnamese monitoring
  stations. Ingests OpenAQ (PM/gas) + Open-Meteo ERA5 (weather) → S3 → Glue (partition projection) →
  Athena/dbt marts → GeoJSON HTTP API + Leaflet map. Gated SARIMA forecaster + gated QuickSight BI.
- **AWS account:** 703668403514, region `ap-southeast-1`. Cost ≈ **$3.22/mo** (hard ~$8 budget alarm).
- **Source of truth:** the codebase + **live AWS**. Docs are reconciled snapshots, not authority.

---

## Current Live State (verified 2026-05-31, do not trust stale "torn down" notes)

- **Compute layer is LIVE.** 5 Lambdas deployed: `openaq_batch_sync`, `openaq_streaming_producer`,
  `openaq_weather_ingest`, `openaq_aqi_api`, `openaq_completeness_check`. `openaq_forecast_generate`
  is **gated/absent** (deploys only when `var.forecast_lambda_image_uri != ""`).
- **5 EventBridge schedules ENABLED** (batch daily, streaming 30-min, weather daily, dbt daily,
  completeness hourly). Stream receiving data as of today.
- **14 CloudWatch alarms** deployed. Freshness SLA = `DaysSinceLastNewMart` alarm at **21 days**
  (the canonical freshness control; dbt freshness tests are calibrated to match it — see
  `all-transform-dbt.md`).
- **Marts:** `mart_daily_aqi` ≈ 4,704 rows / 17 stations to ~2026-05-28; weather mart ~1 day behind.
  OpenAQ archive normally lags up to ~10 days — that is healthy, not a fault.

> **KNOWN DRIFT — read docs with care.** (1) `docs/DEPLOYED-SPECS-AND-AUDIT.md` §0/§1 predate the
> 2026-05-30 redeploy + secret population — its "compute torn down" / "plaintext key" banners are
> **stale**; current state is LIVE and secret-only. (2) `docs/workshop/*` and
> `docs/architecture.{yaml,png,drawio}` are **NOT** under the no-duplication convention and still
> carry pre-cleanup numbers (5 alarms, 6 Lambdas/schedules, QuickSight-as-deployed). Treat them as
> teaching/legacy, not current fact.

---

## How This File Works (the `all-*.md` Convention)

Every `process/context/` directory has one `all-*.md` entrypoint acting as the attachable quick router
for that domain. This root file is the top-level router. Agents: read `all-context.md` first → find the
relevant group → read that group's `all-{group}.md` → only then load the specific deep doc.

No `README.md` files inside `process/context/`. Canonical entrypoints use `all-*.md`.

---

## Canonical Document Owners (no-duplication convention)

Each fact has ONE canonical owner; others link to it so they cannot drift. (Defined in `README.md`.)

| Concern | Canonical owner |
|---|---|
| Machine facts: AWS IDs, S3 prefixes, dbt facts, station roster, rules | `CLAUDE.md` |
| As-deployed resource inventory + audit | `docs/DEPLOYED-SPECS-AND-AUDIT.md` (mind stale §0/§1) |
| Design rationale + headline metrics | `docs/PIPELINE-REPORT.md` |
| Data flow + governance (ingest→mart, retention, DQ gates) | `docs/DATA-LIFECYCLE.md` |
| Quality assessment + open items | `docs/ARCHITECTURE-EVALUATION.md` |
| How we research (the 5-lane method + HARD GATE) | `docs/RESEARCH-WORKFLOW.md` |
| How we operate (runbooks, deliberate non-changes) | `docs/OPERATIONS-RUNBOOK.md` |
| Build from scratch (bilingual EN/VI) | `docs/workshop/5.1–5.6` (legacy numbers) |

---

## Context Groups

| Group | Entry point | Scope |
|---|---|---|
| `ingestion-lambdas` | `process/context/ingestion-lambdas/all-ingestion-lambdas.md` | batch_sync, streaming_producer, weather_ingest; Kinesis/Firehose; Secrets Manager; OpenAQ/Open-Meteo sources |
| `transform-dbt` | `process/context/transform-dbt/all-transform-dbt.md` | dbt-on-Athena: staging→intermediate→marts, seeds, singular tests, freshness gates, Glue tables. **Highest data-correctness blast radius.** |
| `infra-terraform` | `process/context/infra-terraform/all-infra-terraform.md` | All `terraform/*.tf`, workgroup/enforcement, partition projection, `_qs_disabled/`, build pipeline |
| `serving-api-dashboard` | `process/context/serving-api-dashboard/all-serving-api-dashboard.md` | aqi_api Lambda, API Gateway, GeoJSON, Leaflet dashboard |
| `domain-data-quality` | `process/context/domain-data-quality/all-domain-data-quality.md` | AQI/health science, DQ filters, sensor correction, station roster semantics. **Correctness-critical; see open defect.** |
| `deployment-ops` | `process/context/deployment-ops/all-deployment-ops.md` | CI, monitoring/alarms, completeness_check, key rotation, redeploy, gated subsystems |

---

## Task Routing Table

| If the task involves... | Start with | Then load |
|---|---|---|
| architecture / stack questions | this file | the relevant group `all-*.md` |
| batch / streaming / weather ingest | this file | `ingestion-lambdas/all-ingestion-lambdas.md` |
| dbt models / marts / freshness / Glue | this file | `transform-dbt/all-transform-dbt.md` |
| Terraform / workgroup / partitions / deploy infra | this file | `infra-terraform/all-infra-terraform.md` |
| API / GeoJSON / dashboard | this file | `serving-api-dashboard/all-serving-api-dashboard.md` |
| AQI / health metrics / DQ / sensor correction | this file | `domain-data-quality/all-domain-data-quality.md` |
| CI / alarms / runbooks / key rotation / forecast gate | this file | `deployment-ops/all-deployment-ops.md` |
| opening a development cycle (how to research) | `docs/RESEARCH-WORKFLOW.md` | the relevant lane(s) |

---

## Constraint Envelope (standing adversarial filter — RESEARCH-WORKFLOW Lane 5)

Every recommendation must pass: **≤ ~$3–8/mo · single operator · serverless/scale-to-zero ·
QuickSight Standard (BI gated) · ~5 actively-reporting stations · local Terraform state (deliberate).**
Pre-reject as out-of-envelope (flag, don't propose): Timestream hot-path dual-write, Lake Formation
fine-grained governance, Iceberg migration, EMR/Redshift, LSTM/Transformer forecasting, Amazon Forecast
(closed to new customers since 2024-07-29 — gated SARIMA-in-Lambda is the correct choice).

---

## Repository Structure

```
vietnam-air-quality-pipeline/
  terraform/         -- IaC: main, glue_tables, kinesis, lambda, monitoring, secrets, variables, outputs
                        + _qs_disabled/ (parked QuickSight, not loaded by TF)
  lambda/            -- batch_sync, streaming, weather_ingest, aqi_api, completeness_check,
                        forecast_generate (gated container); shared/; tests/ (85 tests); build.sh
  transform/         -- dbt project openaq_transform (dbt-athena-community)
                        models/{staging,intermediate,marts}, seeds/, tests/ (4 singular), buildspec_dbt.yml
  ingestion/         -- historical/sync_historical.sh + station_ids.txt (roster copy — drift surface)
  dashboard/         -- index.html (Leaflet), serve.py, demo_data.json
  docs/              -- 7 analysis docs + workshop/ (bilingual) + architecture.{yaml,png,drawio}
  .github/workflows/ -- validate.yml (tf fmt/validate, pytest, dbt parse), diagram.yml
  process/           -- RIPER-5 harness: context (this), general-plans, (features when needed)
```

---

## Context Update Protocol

When durable project knowledge changes: (1) update the smallest relevant context file, (2) update this
file if routing/ownership/groups changed, (3) update the owning `all-{group}.md`, (4) re-verify any
live-state claim against AWS before committing it (RESEARCH-WORKFLOW HARD GATE).

## Scan Metadata

- Generated: 2026-05-31 by parallel research agents (kit audit, doc inventory, domain fact-check,
  AWS/agent practices) + live AWS probes (lambda list-functions, scheduler list-schedules, athena).
- Method: read-only research/audit phase; findings synthesized before any file write.

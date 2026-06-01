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
- **Project type:** AWS **portfolio / demo** for the **First Cloud Journey (FCJ)** program — not a
  funded service, no real users, no regulatory consumer. Business/proposal framing →
  `docs/BUSINESS-CONTEXT.md`; the FCJ *workshop* half is `docs/workshop/5.1–5.6`.
- **Source of truth:** the codebase + **live AWS**. Docs are reconciled snapshots, not authority.

---

## Current Live State (verified 2026-05-31, do not trust stale "torn down" notes)

- **Compute layer is LIVE.** 6 Lambdas deployed: `openaq_batch_sync`, `openaq_streaming_producer`,
  `openaq_weather_ingest`, `openaq_aqi_api`, `openaq_completeness_check`, and (since 2026-06-01)
  `openaq_forecast_generate` — the SARIMA forecaster is now **ENABLED** (`var.forecast_lambda_image_uri`
  set in tfvars; image in ECR). It writes `mart_daily_forecast` (35 rows / 5 active stations / 7-day
  horizon, avg holdout RMSE ≈18 µg/m³), surfaced via `GET /analytics/forecast` + the dashboard
  **Forecast Monitor** sheet.
- **5 EventBridge schedules ENABLED** (batch daily, streaming 30-min, weather daily, dbt daily,
  completeness hourly). Stream receiving data as of today.
- **14 CloudWatch alarms** deployed. Freshness SLA = `DaysSinceLastNewMart` alarm at **21 days**
  (the canonical freshness control; dbt freshness tests are calibrated to match it — see
  `all-transform-dbt.md`).
- **Marts:** `mart_daily_aqi` = 4,743 rows / 17 stations, `2023-01-01 → 2026-05-28` (live-probed
  2026-05-31 via Athena, 46.6 KiB scanned); weather mart ~1 day behind.
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

Each fact has ONE canonical owner; others link to it so they cannot drift. (Defined in the root `README.md`.)

| Concern | Canonical owner |
|---|---|
| Business / proposal framing (what & why, audience, non-goals, success) | `docs/BUSINESS-CONTEXT.md` |
| Machine facts: AWS IDs, S3 prefixes, dbt facts, station roster, rules | `CLAUDE.md` |
| As-deployed resource inventory + audit | `docs/DEPLOYED-SPECS-AND-AUDIT.md` (mind stale §0/§1) |
| Design rationale + headline metrics | `docs/PIPELINE-REPORT.md` |
| Data flow + governance (ingest→mart, retention, DQ gates) | `docs/DATA-LIFECYCLE.md` |
| Quality assessment + open items | `docs/ARCHITECTURE-EVALUATION.md` |
| Well-Architected grounding (6 pillars + Data Analytics Lens) + accepted-risk register | `docs/WELL-ARCHITECTED.md` |
| Data-quality test strategy (generic/singular/unit/expectations/freshness) | `docs/DATA-QUALITY.md` |
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

Two **process-support groups** back the RIPER-5 harness (cross-cutting, not domain knowledge):

| Group | Entry point | Scope |
|---|---|---|
| `tests` | `process/context/tests/all-tests.md` | test surfaces (Lambda pytest, dbt tests, CI), how to run, verification gates for plans |
| `planning` | `process/context/planning/all-planning.md` | where plans live, simple vs complex depth, the worked `example-complex-prd.md` template |

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
| running/writing tests, verification gates, debugging | this file | `tests/all-tests.md` |
| writing a plan / PLAN phase / spec depth | this file | `planning/all-planning.md` |
| opening a development cycle (how to research) | `docs/RESEARCH-WORKFLOW.md` | the relevant lane(s) |

---

## Constraint Envelope (standing adversarial filter — RESEARCH-WORKFLOW Lane 5)

Every recommendation must pass: **≤ ~$3–8/mo · single operator · serverless/scale-to-zero ·
QuickSight Standard (BI gated) · ~5 actively-reporting stations · remote S3 Terraform state (no DynamoDB).**
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
  docs/              -- 9 analysis docs + workshop/ (bilingual) + architecture.{yaml,png,drawio}
  .github/workflows/ -- validate.yml (tf fmt/validate, pytest, dbt parse), diagram.yml
  process/           -- RIPER-5 harness: context (this), general-plans, (features when needed)
```

---

## Technology Stack

| Layer | Technology |
|---|---|
| Ingestion | Python 3.12 Lambdas (arm64); OpenAQ S3 archive + REST v3; Open-Meteo ERA5; Kinesis stream |
| Storage | S3 (raw `raw/batch`, `raw/stream`; processed `processed/openaq_mart`); Intelligent-Tiering |
| Catalog / query | AWS Glue (partition projection) + Athena (`openaq_workgroup`, 10 GB scan cap) |
| Transform | dbt (`dbt-athena-community`), project `openaq_transform`: staging → intermediate → marts |
| Serving | API Gateway + `openaq_aqi_api` Lambda (GeoJSON/CORS) → static Leaflet dashboard |
| Forecasting | gated SARIMA-in-Lambda (ECR container), 7-day PM2.5 — deploy-gated, off by default |
| Orchestration | EventBridge Scheduler → Lambdas; CodeBuild for the daily dbt run |
| IaC / CI | Terraform (remote S3 state + native lock, no DynamoDB; adopted 2026-05-31); GitHub Actions `validate.yml` (tf fmt/validate, pytest, dbt parse) |
| Secrets | AWS Secrets Manager (OpenAQ API key); no plaintext keys in code |
| Region / account | `ap-southeast-1` / `703668403514` · cost ≈ $3.22/mo |

Exact IDs, prefixes, runtimes, and the station roster are owned by `CLAUDE.md` (do not duplicate here).

---

## Context Group Lifecycle

Groups are created and retired on evidence, not speculation:

- **Create** a group `{name}/` with an `all-{name}.md` entrypoint once ≥ 3 related deep docs exist, or
  when a distinct knowledge domain (or a harness-support concern like `tests`/`planning`) is routed to
  repeatedly. Every `process/context/` directory MUST have exactly one `all-{name}.md` router.
- **Index** every new group from this root router's *Context Groups* + *Task Routing* tables, and index
  each deep doc from its group's `all-{name}.md`. An unindexed doc is invisible to agents and fails
  `vc-audit-context`.
- **Update** the smallest relevant doc first, then its group router, then this file if
  routing/ownership/groups changed (see *Context Update Protocol* below).
- **Retire** a group by folding its docs into a surviving group and removing the empty directory; never
  leave a directory without its `all-{name}.md`.
- **Audit** with `node .claude/skills/vc-audit-context/scripts/validate-context-discovery.mjs` after any
  structural change to context.

Current groups: 6 domain (`ingestion-lambdas`, `transform-dbt`, `infra-terraform`,
`serving-api-dashboard`, `domain-data-quality`, `deployment-ops`) + 2 process-support (`tests`,
`planning`).

---

## Source References / Key Files

The canonical knowledge sources behind this router:

- Business / proposal framing (portfolio-demo intent, audience, non-goals) → `docs/BUSINESS-CONTEXT.md`
- Machine facts, AWS IDs, station roster, rules → `CLAUDE.md`
- Deployed inventory + audit → `docs/DEPLOYED-SPECS-AND-AUDIT.md`
- Design rationale + metrics → `docs/PIPELINE-REPORT.md`; data flow → `docs/DATA-LIFECYCLE.md`
- Research method (5 lanes + HARD GATE) → `docs/RESEARCH-WORKFLOW.md`; ops → `docs/OPERATIONS-RUNBOOK.md`
- Well-Architected review (6 pillars + Data Analytics Lens, accepted-risk register) → `docs/WELL-ARCHITECTED.md`
- dbt test strategy (generic/singular/unit/dbt-expectations/freshness) → `docs/DATA-QUALITY.md`
- Harness rules → `process/development-protocols/all-development-protocols.md`
- Group routers → `process/context/{group}/all-{group}.md` (this file is the root: `process/context/all-context.md`)

---

## Open Questions / Outstanding Work

- Open production-hardening items: `docs/ARCHITECTURE-EVALUATION.md` Resolution status — remote Terraform
  state backend DONE (2026-05-31); API WAF deliberately DECLINED (out-of-envelope). No in-envelope
  production-hardening items remain open.
- NO₂/O₃/SO₂/CO AQI sub-indices not yet in the mart (see `planning/example-complex-prd.md` for the NO₂ shape).
- SARIMA forecaster is **LIVE** (2026-06-01) — was deploy-gated; now produces `mart_daily_forecast` and
  powers the Forecast Monitor sheet. Minor follow-up: the `openaq-forecast-image` CodeBuild project isn't
  Terraform-managed (image rebuilds need a manual combined-zip step) — see the completed SARIMA plan.
- QuickSight BI is parked in `terraform/_qs_disabled/` (out of envelope by default).

---

## Context Update Protocol

When durable project knowledge changes: (1) update the smallest relevant context file, (2) update this
file (`process/context/all-context.md`) if routing/ownership/groups changed, (3) update the owning
`all-{group}.md`, (4) re-verify any live-state claim against AWS before committing it
(RESEARCH-WORKFLOW HARD GATE).

## Scan Metadata

- Generated: 2026-05-31 by parallel research agents (kit audit, doc inventory, domain fact-check,
  AWS/agent practices) + live AWS probes (lambda list-functions, scheduler list-schedules, athena).
- Repo HEAD at generation: branch `main`, commit `092c037` (RIPER-5 harness install); refreshed during
  the kit-wiring completion pass. Re-run `git rev-parse HEAD` to confirm the current commit.
- Method: read-only research/audit phase; findings synthesized before any file write.
- Live-state verification (2026-05-31, HARD GATE): read-only AWS probes confirmed 5 Lambdas
  (`forecast_generate` absent/gated), 5 EventBridge schedules all ENABLED, 14 openaq CloudWatch
  alarms, and `mart_daily_aqi` = 4,743 rows / 17 stations via Athena. Specs match ground truth.

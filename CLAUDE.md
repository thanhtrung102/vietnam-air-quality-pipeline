# Vietnam Air Quality Pipeline — Project Context

> Canonical source for project **facts**: AWS IDs, S3 prefixes, dbt facts, the station roster, and
> rules. The deployed **resource inventory** lives in `docs/DEPLOYED-SPECS-AND-AUDIT.md`; the doc map
> is in `README.md`.
>
> **Context router:** `process/context/all-context.md` is the root entrypoint for repo knowledge
> (architecture, the 6 context groups, live-state, known-drift caveats, task routing). Read it first
> for any substantial planning/research/implementation task, then load the relevant `all-{group}.md`.

## AWS Configuration
- **Region:** ap-southeast-1
- **S3 bucket name:** openaq-pipeline-thanhtrung102
- **Athena workgroup:** openaq_workgroup
- **Glue database:** openaq_raw
- **Kinesis stream name:** openaq_stream

## S3 Prefixes
- **Historical batch:** `raw/batch/locationid={id}/year={year}/month={month}/`
- **Streaming:** `raw/stream/{year}/{month}/{day}/{hour}/`
- **Processed marts:** `processed/openaq_mart/{table}/{uuid}/` (dbt CTAS via `s3_data_dir`; workgroup enforcement is OFF so dbt writes here, not under `athena-results/`)

## dbt
- **Project name:** openaq_transform
- **Adapter:** dbt-athena-community
- **Mart table partitions on:** measurement_date (date-grain marts; `mart_forecast_accuracy` partitions on forecast_date). Analytical/aggregate marts use `partitioned_by = []` (unpartitioned).
- **Mart table clustering:** none — no mart uses clustering or bucketing (no `bucketed_by`). Partition projection alone keeps Athena scans small.

## Naming Conventions
- All identifiers: snake_case
- All AWS resources prefixed with: `openaq_`

## OpenAQ
- **Public archive bucket:** openaq-data-archive (us-east-1)
- **Archive file naming:** `location-{location_id}-{YYYYMMDD}.csv.gz`
- **Archive schema columns (9):** location_id, sensors_id, location, datetime, lat, lon, parameter, units, value
- **datetime format:** ISO-8601 string with `+07:00` offset — cast with `from_iso8601_timestamp(datetime)` in Athena
- **Sentinel value:** `-999.0` means missing — always filter `WHERE value != -999.0` in staging
- **Vietnamese station IDs (19 confirmed in archive):**

| ID | City | Name | Active |
|----|------|------|--------|
| 7441 | Hanoi | US Embassy Hanoi | to 2025-04 |
| 2539 | Hanoi | US Diplomatic Post Hanoi (predecessor) | 2016 only |
| 1285357 | Hanoi | SPARTAN - Vietnam Acad. Sci. | to 2020-06 |
| 2161290 | Hanoi | An Khánh | to 2025-06 |
| 2161291 | Hanoi | Cầu Diễn | to 2024-12 |
| 2161292 | Hanoi | Số 46 Lưu Quang Vũ | **active** |
| 2161316 | Hanoi | Thành Công | to 2024-02 |
| 2161317 | Hanoi | Thanh Xuân - Sóc Sơn | to 2024-09 |
| 2161318 | Hanoi | Tứ Liên | to 2024-03 |
| 2161319 | Hanoi | Vân Đình | to 2025-02 |
| 2161320 | Hanoi | Vân Hà | to 2025-06 |
| 2161321 | Hanoi | Văn Quán | to 2024-04 |
| 2161323 | Hanoi | Xuân Mai | to 2025-03 |
| 4946812 | Hanoi | Công viên Nhân Chính | **active** |
| 4946813 | Hanoi | Số 1 Giải Phóng - Bạch Mai | **active** |
| 4946811 | Hanoi | 556 Nguyễn Văn Cừ | **active** (2025–) |
| 6123215 | Hanoi area | OceanPark (20.9933°N, 105.9441°E, Hanoi-adjacent) | **active** since 2025-11-08 |
| 7440 | Ho Chi Minh City | US Diplomatic Post HCMC | to 2025-03 |
| 2446 | Ho Chi Minh City | US Diplomatic Post HCMC (predecessor) | 2016 only |
| 6068138 | Ho Chi Minh City | Care Centre | to 2025-12 |
| 6273386 | Ho Chi Minh City | VNUHCMUS Campus 1 | **active** |

- The table above is the authoritative roster (mirrored by the `vn_stations` dbt seed). Data-quality
  notes and exclusion rationale: `docs/workshop/5.1-introduction.md` (Data Description) and
  `docs/DATA-LIFECYCLE.md` §7.

## IAM
- **Local dev user:** terraform-admin (pre-existing, not managed by Terraform)
- **Orchestration:** EventBridge Scheduler + Lambda (terraform/lambda.tf) — Kestra Docker not available on build machine
- **Lambda runtime:** python3.12
- **Lambda functions (6 defined in terraform/lambda.tf):**
  - `openaq_batch_sync` (512 MB, 900s timeout, daily at 01:00 UTC) — OpenAQ S3 archive historical sync
  - `openaq_streaming_producer` (256 MB, 120s timeout, every 30 minutes) — OpenAQ REST API v3 → Kinesis
  - `openaq_weather_ingest` (256 MB, 300s timeout, daily at 02:00 UTC) — Open-Meteo ERA5 → S3
  - `openaq_aqi_api` (behind API Gateway, GeoJSON/CORS) — serves the Leaflet dashboard
  - `openaq_completeness_check` (hourly) — emits MissingStations + DaysSinceLastNewMart CloudWatch metrics
  - `openaq_forecast_generate` (ECR container image, SARIMA 7-day PM2.5) — **gated/not deployed by default**: created only when `var.forecast_lambda_image_uri != ""` (`count`-gated in lambda.tf). Requires building and pushing the ECR image first.
- **EventBridge schedules:** openaq_batch_daily, openaq_streaming_30min, openaq_weather_daily, openaq_dbt_daily (CodeBuild), openaq_completeness_hourly, openaq_forecast_daily (forecast schedule is also gated on the forecast image)

## Research method
- Open every development cycle with `docs/RESEARCH-WORKFLOW.md` — the project's reusable research
  workflow (live-state recon, domain-correctness check, reference-arch grounding, data-eng rigor,
  constraint envelope). Verify findings against live AWS before they inform a plan.

## Rules
- **Never hardcode API keys** — always read from environment variables

---

## RIPER-5 Agent Harness

This repo uses the RIPER-5 spec-driven workflow (orchestrator + specialist subagents). The harness was
installed for this data-engineering project (data-eng subset: no UI/web/browser agents).

- **Orchestrator role:** detect intent → route to a specialist subagent → pass context → monitor
  compliance. Don't do research/planning/implementation directly for non-trivial work — delegate.
- **Shared protocols (read as needed):** `process/development-protocols/all-development-protocols.md`
  is the router. **`live-state-verification.md` is the HARD GATE** — any claim about deployed state or
  real data must be settled by a read-only probe against ground truth before it enters a plan or a
  "done" claim (this project's core discipline; see also `docs/RESEARCH-WORKFLOW.md`).
- **Context:** `process/context/all-context.md` is the root router (6 groups + live-state + drift
  caveats). Read it before substantial planning/research.
- **Specialist agents:** `.claude/agents/` (research, innovate, plan, execute, fast-mode,
  update-process, debugger, tester, git-manager, code-reviewer, code-simplifier).
- **Skills:** `.claude/skills/` (generate-context, generate-plan, scout, security, sequential-thinking,
  problem-solving, audit-context/plans/vc, debug, context-engineering, docs, docs-seeker, predict,
  scenario).
- **Plans:** `process/general-plans/{active,completed}/`; date-stamped `{date}-{slug}_PLAN.md`.
- **Codex parity:** `.codex/agents/` mirrors `.claude/agents/`; `.agents/skills/` mirrors
  `.claude/skills/`. See `AGENTS.md`.

# Vietnam Air Quality Pipeline

A fully serverless, end-to-end analytics pipeline for Vietnamese air-quality data on AWS —
ingestion → catalog → dbt transforms → GeoJSON API + live map, with operational monitoring and
short-term PM2.5 forecasting. Runs at **~$3.22/month** on a single account, scale-to-zero.

> Region `ap-southeast-1` · Solution-style IaC (Terraform) · OpenAQ + Open-Meteo open data.

---

## Business problem

Vietnam — especially Hanoi and Ho Chi Minh City — has health-critical PM2.5 pollution, but the data
is fragmented and hard to act on. OpenAQ exposes it only through a **lagging, requester-pays S3
archive** plus a **rate-limited real-time API**, across ~21 stations (many inactive, some emitting
artefact readings). There is no single, queryable, health-framed, forecast-capable view.

**Goal:** one source of truth that shows, per station, current AQI, historical trends,
health-equivalent metrics (US-EPA category, WHO/QCVN exceedance, cigarette-equivalent), and a
short-term forecast — cheaply and reproducibly.

## Constraints

- **Cost** — single personal AWS account, hard ~$8/mo budget alarm (actual ≈ $3.22/mo): must be
  serverless and scale-to-zero (no EMR / Redshift / brokers).
- **Data sources** — OpenAQ archive is requester-pays (us-east-1) and publishes with a
  multi-day-to-month lag; the real-time API is key-gated + rate-limited; only ~21 VN stations exist
  and only ~5 actively report.
- **Data quality** — `-999` sentinels (~3.8%), implausible spikes, one biased outlier station
  (`6273386`), low-cost-sensor humidity overread, and parameters with differing averaging windows.
- **Operational** — no full-time ops, so the pipeline must self-monitor and alert; QuickSight is
  **Standard** (BI dashboard gated off); Terraform uses local state; AWS-Solutions-style reproducibility.

## Proposed solution — serverless medallion pipeline

- **Ingest (3 Lambdas):** `batch_sync` (historical archive → S3, idempotent ETag-skip),
  `streaming_producer` (real-time API → Kinesis → Firehose → S3), `weather_ingest`
  (Open-Meteo ERA5 → S3).
- **Land + catalog:** S3 raw zone + Glue **partition projection** (no Crawler; ~63 KB scanned/query
  vs an ~800 MB table).
- **Transform:** **dbt-on-Athena** via CodeBuild — staging views → intermediate tables (21-station
  seed allowlist) → marts (EPA-2024 AQI, health-equivalents, ML lag features), materialized as
  Parquet under `processed/openaq_mart/`.
- **Serve:** API Gateway + `aqi_api` Lambda → GeoJSON → Leaflet map; **gated** SARIMA forecast and
  QuickSight dashboard (enabled only when their prerequisites are supplied).
- **Operate:** EventBridge schedules, X-Ray on all Lambdas, CloudWatch custom metrics + **14 alarms**,
  SNS email, SQS DLQs, hourly completeness + mart-freshness monitoring, secret in Secrets Manager,
  10 GB Athena scan cap, and tiered S3 lifecycle for cost control.

```
EventBridge ─► batch_sync   ◄─ OpenAQ S3 archive (CSV.GZ)   ─► raw/batch/
            ─► streaming     ◄─ OpenAQ REST v3 ─► Kinesis ─► Firehose ─► raw/stream/
            ─► weather_ingest◄─ Open-Meteo ERA5             ─► raw/weather/
                                    │
                 Glue (partition projection) ─► Athena ─► dbt (CodeBuild) ─► processed/openaq_mart/
                                    │                                              │
                 completeness_check ┘                 aqi_api ─► API Gateway ─► Leaflet map
```

See [`docs/architecture.png`](docs/architecture.png) for the full diagram, and
[`docs/PIPELINE-REPORT.md`](docs/PIPELINE-REPORT.md) for the design-decision rationale.

---

## Documentation map

Each document owns one concern — read the one that matches your question.

| Doc | Read it when you need… | Concern |
|---|---|---|
| **[CLAUDE.md](CLAUDE.md)** | exact AWS IDs, S3 prefixes, dbt facts, station roster, rules | machine-facing project facts |
| **[docs/PIPELINE-REPORT.md](docs/PIPELINE-REPORT.md)** | the architecture narrative, *why* each choice was made, headline metrics | design + rationale |
| **[docs/DEPLOYED-SPECS-AND-AUDIT.md](docs/DEPLOYED-SPECS-AND-AUDIT.md)** | the exact as-deployed resource inventory + audit findings | deployed state of record |
| **[docs/DATA-LIFECYCLE.md](docs/DATA-LIFECYCLE.md)** | how a reading flows ingest→mart, retention rules, DQ gates | data flow + governance |
| **[docs/ARCHITECTURE-EVALUATION.md](docs/ARCHITECTURE-EVALUATION.md)** | the scored multi-lens evaluation + what's still open | quality assessment |
| **[docs/RESEARCH-WORKFLOW.md](docs/RESEARCH-WORKFLOW.md)** | to open a development cycle — the reusable research method (live-state, domain-correctness, reference-arch, data-rigor, constraint lanes) | how we research |
| **[docs/OPERATIONS-RUNBOOK.md](docs/OPERATIONS-RUNBOOK.md)** | runbook procedures (OpenAQ key rotation, dbt redeploy) + deliberate out-of-envelope non-changes (e.g. remote TF state) | how we operate |
| **[docs/workshop/5.1–5.6](docs/workshop/5.1-introduction.md)** | to build/deploy it from scratch (bilingual EN/VI) | step-by-step runbook |

**Source of truth:** the codebase + **live AWS** (verified against account `703668403514`,
`ap-southeast-1`). The four `docs/*.md` analysis files and `CLAUDE.md` were last reconciled against
live state on **2026-05-30**.

**No-duplication convention:** each fact has one canonical owner and the others link to it, so they
cannot drift. Canonical owners — **facts/roster:** `CLAUDE.md`; **deployed resource inventory:**
`docs/DEPLOYED-SPECS-AND-AUDIT.md`; **design rationale + metrics:** `docs/PIPELINE-REPORT.md`;
**data flow + governance:** `docs/DATA-LIFECYCLE.md`; **quality assessment:** `docs/ARCHITECTURE-EVALUATION.md`.

---

## Quick start

Deploy from scratch by following the workshop in order, starting at
[5.2 Prerequisites](docs/workshop/5.2-prerequisites.md). In brief:

```bash
bash lambda/build.sh                 # build the 5 Lambda deployment zips
cd terraform && terraform init
terraform apply                      # provision the pipeline
# then populate the OpenAQ API key into Secrets Manager (see workshop 5.2)
```

## Verified state (live-probed 2026-05-31)

A derived at-a-glance snapshot — **not a canonical owner**. Each fact's owner is linked; re-probe
against live AWS (RESEARCH-WORKFLOW HARD GATE) rather than trusting this table after its date.

| Aspect | Value | Owner |
|---|---|---|
| Deployed Lambdas | 5 (python3.12 / arm64 / X-Ray); `forecast_generate` gated off | [DEPLOYED-SPECS](docs/DEPLOYED-SPECS-AND-AUDIT.md) |
| Stations | 21 in roster (17 Hanoi, 4 HCMC); 5 actively reporting | [CLAUDE.md](CLAUDE.md) |
| `int_measurements_enriched` | 1,394,784 rows | [PIPELINE-REPORT](docs/PIPELINE-REPORT.md) |
| `mart_daily_aqi` | 4,743 rows / 17 stations (2023-01-01 → 2026-05-28) | [PIPELINE-REPORT](docs/PIPELINE-REPORT.md) |
| dbt marts location | `processed/openaq_mart/{table}/{uuid}` (Intelligent-Tiering) | [DATA-LIFECYCLE](docs/DATA-LIFECYCLE.md) |
| Athena workgroup | 10 GB scan cap + SSE_S3 as **defaults** (`enforce=false`) | [DEPLOYED-SPECS](docs/DEPLOYED-SPECS-AND-AUDIT.md) |
| CloudWatch alarms | 14 (incl. per-function Errors, DLQ-depth, mart-staleness) | [DEPLOYED-SPECS](docs/DEPLOYED-SPECS-AND-AUDIT.md) |
| Lambda unit tests | 85 passed / 0 failed *(re-run live 2026-05-31)* | [tests context](process/context/tests/all-tests.md) |
| Cost | ≈ $3.22 / month *(estimate)* | [PIPELINE-REPORT](docs/PIPELINE-REPORT.md) |

## RIPER-5 agent harness

This repo runs the [vibecode-pro-max-kit](https://github.com/withkynam/vibecode-pro-max-kit)
RIPER-5 spec-driven workflow, installed as a **data-engineering subset** (no UI/web/browser or
kit-maintenance surfaces — see [AGENTS.md](AGENTS.md)). The orchestrator detects intent, routes to a
specialist sub-agent, and enforces the live-state-verification HARD GATE before any claim about
deployed AWS or real data enters a plan or a "done" report. Project context routes through
[`process/context/all-context.md`](process/context/all-context.md); shared workflow rules live in
[`process/development-protocols/all-development-protocols.md`](process/development-protocols/all-development-protocols.md).

Run the harness self-audit any time with `node .claude/skills/vc-audit-vc/scripts/*.mjs` and
`node .claude/skills/vc-audit-context/scripts/*.mjs` (see the `vc-audit-vc` / `vc-audit-context`
skills). `.claude/agents/` is canonical; `.codex/agents/*.toml` mirror them and `.agents/skills/`
mirrors `.claude/skills/` for Codex discovery.

### Agents

| Agent | Phase / role |
|---|---|
| `vc-research-agent` | RESEARCH — read-only codebase + external fact-gathering |
| `vc-innovate-agent` | INNOVATE — explore 2-3 approaches with trade-offs |
| `vc-plan-agent` | PLAN — write the spec with blast-radius analysis |
| `vc-execute-agent` | EXECUTE — implement to plan with a 50% check-in |
| `vc-fast-mode-agent` | Compressed RESEARCH→INNOVATE→PLAN for small changes |
| `vc-update-process-agent` | UPDATE PROCESS — capture learnings, scan for stale artifacts |
| `vc-debugger` | Evidence-first debugging with hypothesis testing |
| `vc-tester` | Diff-aware test running with auto-escalation |
| `vc-code-reviewer` | Edge-case scout + security/correctness review |
| `vc-code-simplifier` | Clarity refactoring with no behavior change |
| `vc-git-manager` | Logical commit splitting from touched files |

### Skills Catalog

| Skill | Use it for |
|---|---|
| `vc-generate-context` | author/refresh `process/context/` knowledge docs |
| `vc-generate-plan` | scaffold a date-stamped `_PLAN.md` artifact |
| `vc-audit-context` | audit context routing, grouping, and discoverability |
| `vc-audit-plans` | audit the plan/feature inventory for drift |
| `vc-audit-vc` | audit harness health (agent parity, skills, README sync, protocols, seeds) |
| `vc-scout` | scoped internal/external scouting before deeper work |
| `vc-security` | STRIDE + OWASP review and secret-pattern scanning |
| `vc-debug` | systematic root-cause debugging methodology |
| `vc-sequential-thinking` | structured step-by-step reasoning for hard problems |
| `vc-problem-solving` | lateral problem-solving techniques when stuck |
| `vc-predict` | multi-persona debate to pressure-test a decision |
| `vc-scenario` | enumerate edge cases and failure scenarios |
| `vc-context-engineering` | context-window optimization and compression patterns |
| `vc-docs` | initialize/summarize/update project documentation |
| `vc-docs-seeker` | research-safe library/API documentation lookup |

---

## License / attribution

Data: [OpenAQ](https://openaq.org) (air quality) and [Open-Meteo ERA5](https://open-meteo.com)
(weather reanalysis). Built as a portfolio data-engineering project.

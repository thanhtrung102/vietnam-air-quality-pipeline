# Research Workflow — project reference

> The reusable research method for this pipeline. It extends the base kit (RIPER-5 RESEARCH +
> deep-research fan-out + adversarial verify) with the lanes a **deployed, regulated-domain data
> pipeline** needs. Use it to open every development cycle. Last updated 2026-05-30.

## Why the base kit isn't enough here

The kit's RESEARCH mode is read-only, parallel, and adversarially verified — but it is **code-centric,
generic, and constraint-agnostic**. For a *deployed* air-quality *data* product it has four blind spots:
the live system, the domain's correctness standards, external reference architectures, and the project's
own cost/operational envelope. The lanes below close those.

## The five research lanes

Run the relevant lanes in parallel (kit fan-out), then synthesize and **adversarially verify** before
proposing anything. Not every cycle needs all five — pick by task.

### Lane 1 — Live-state recon (read-only) **[always, for deployed changes]**
Ground truth is **live AWS**, not the repo (state drifts). Read-only probes only:
- `aws athena` row counts / `MAX(measurement_date)` / freshness; `aws glue get-table` locations.
- `aws lambda get-function-configuration`, `aws cloudwatch describe-alarms`, `list-metrics`.
- tail CloudWatch logs; `aws s3 ls` prefixes.
*Payoff seen:* surfaced the `batch_sync` `MissingContentLength` data-loss bug (5 active stations
silently not syncing) that was invisible to code/infra review; caught doc drift (enforce flag, alarm
count, mart location).

### Lane 2 — Domain-correctness check **[for any AQI / health / sensor computation]**
Cite the authoritative standard, then diff the code against it. **Project domain checklist:**
- **EPA AQI breakpoint table must be post-2024** (PM2.5): 50↔9.0, 100↔35.4, 150↔55.4, 200↔**125.4**,
  300↔**225.4**, 500↔**325.4**. (Pre-2024 used 12.0/150.4/250.4/350.4/500.4 — wrong.)
  *Status 2026-05-30: CORRECT in `mart_daily_air_quality.sql` + `mart_health_summary.sql`.*
- **Daily AQI = local-midnight (UTC+7) 24-h mean, truncated to 0.1 µg/m³** before breakpoints.
  *Status 2026-05-30: day-window CORRECT — `cast(timestamp-with-tz AS date)` keeps the +07:00 local
  date (verified live: `01:00+07:00` → date `2023-01-01`). Note: `measured_at` is UTC-rebased while
  `measurement_date` is local — harmless for date-grouped daily marts, a trap for any sub-daily logic.*
- **NowCast** (12-h weighted, `w=max(c_min/c_max, 0.5)`) is required for any *"current conditions"*
  view; daily AQI is not a live number.
- **Low-cost sensors (3× AirGradient/PMS5003):** RH over-read at high humidity is real, but **do not
  blind-apply the Barkjohn US PurpleAir coefficients** (`0.524·PA − 0.0862·RH + 5.75`) — they're
  PurpleAir- and US-aerosol-specific. Correct scope = *collocate + fit local coefficients*; until
  then flag low-cost PM2.5 as indicative. (See 2024 high-RH calibration work, AMT 17, 6735.)
- **OpenAQ is unmodified upstream data** — the consumer cleans it: drop `-999` sentinels, negatives,
  suspicious exact-zeros, stuck/repeated values; assert µg/m³ units; dedupe `(station, parameter, ts)`;
  keep reference-grade vs low-cost distinguishable (don't average blindly).

### Lane 3 — Reference-architecture grounding **[for design decisions]**
Validate/challenge choices against authoritative AWS patterns:
- **AWS Well-Architected Data Analytics Lens** (raw→processed→curated, catalog, DQ-as-controlled-change,
  engine-per-job cost) — run via the WA Tool lens catalog.
- **dbt-on-Athena** (BMW Big Data blog): workgroup-per-workload, incremental models, tests-on-PR;
  **CodeBuild as the dbt runner is an AWS-endorsed pattern.**
- **Partition projection** trade-offs (Athena docs): Athena-only (Glue Spark / Redshift Spectrum can't
  see projected partitions); **if >50% of projected partitions are empty, use registered partitions** —
  relevant because station×hour grids go sparse during outages; out-of-range filters return 0 rows silently.
- **Amazon Forecast is closed to new customers (2024-07-29)** → use **SageMaker Canvas / AutoML
  time-series**, not Forecast, for the gated forecaster.

### Lane 4 — Data-engineering rigor **[for transform / quality changes]**
- dbt **singular tests** for domain invariants (composite AQI = max per-pollutant AQI; no `-999`
  survives staging; `composite_aqi` ∈ 0–500); **unit tests (1.8+)** for the AQI bucketing + PM2.5
  tie-break (CI-only, no Athena scan).
- **dbt-expectations** range/set tests (PM2.5 0–1000, RH 0–100, wind 0–360); **Elementary**
  `volume_anomalies`/`freshness_anomalies`/`column_anomalies` (a missed batch sync silently shrinks a
  day-partition — Elementary catches it).
- **Freshness gating on Athena: do NOT use `dbt source freshness`.** dbt-athena computes it from
  Glue metadata (`last_modified`) returned as a string, so it errors on every source regardless of
  actual freshness ([dbt-athena #631](https://github.com/dbt-labs/dbt-athena/issues/631)) — and the
  `loaded_at_field` override the dbt docs say forces query-based freshness is ignored by the adapter.
  *Verified live 2026-05-31:* a CodeBuild run errored on all 3 freshness-configured sources while the
  non-blocking gate masked it as a constant WARN. Instead enforce freshness with a **singular
  query-based test** (`select max(from_iso8601_timestamp(ts)) … having … < current_timestamp - interval`)
  in the non-blocking `dbt test` step, backed by the deployed `DaysSinceLastNewMart` CloudWatch alarm.
  Still enforce `contract: {enforced: true}` on the consumer marts (`mart_daily_aqi`, `mart_daily_air_quality`).
- **Idempotent backfill** = partition overwrite: marts are `partitioned_by=['measurement_date']`, so
  `incremental` + `insert_overwrite` keyed on date is the cheapest idempotent path **when** full-refresh
  scan cost justifies it (not before). Iceberg `merge` + Write-Audit-Publish only if row-level
  upserts/corrections become a requirement.
- **Data observability ≠ infra observability:** a green job can still produce wrong/stale/half-loaded
  data. Watch freshness, volume, distribution, schema, lineage — not just Lambda errors.

### Lane 5 — Constraint envelope (the adversarial filter) **[always]**
Every recommendation must pass: **≤ ~$3–8/mo · single operator · serverless/scale-to-zero ·
QuickSight Standard (BI gated) · ~5 actively-reporting stations · local Terraform state.**
Pre-reject as out-of-envelope (flag, don't propose): Timestream hot-path dual-write, Lake Formation
fine-grained governance, Iceberg migration, LSTM/Transformer forecasting. Right-sized: full-refresh
CTAS until scan cost hurts; SARIMA/Prophet + gradient-boosting-with-meteorology (boundary-layer height,
wind, inversion are the biggest accuracy levers for Hanoi's winter-inversion/monsoon regime).

## How it plugs into the kit / RIPER-5

- **RESEARCH phase:** attach the relevant lanes to the fan-out; Lane 1 + Lane 5 always; Lanes 2/3/4 by
  task type. Synthesize → **adversarially verify each finding against live state** before it informs PLAN.
- **The discipline that matters most:** *verify live; refute the hypothesis.* Don't ship a hypothesis
  as a finding.
- **HARD GATE — any timezone / numeric-correctness / "this is a bug" claim must be settled by a live
  probe against *real data* before it enters a recommendation or a PLAN.** A literal/synthetic probe is
  not enough (it may not match the real data's format), and code-reading alone is not enough (timezone
  cast semantics are non-obvious). This gate is merge-blocking, not a post-hoc check.
  - *Worked example 1:* Lane 2 raised "UTC day-window misalignment"; the live probe **refuted the
    headline** (`measurement_date` is local-correct) and found only the smaller `measured_at` tz nuance.
  - *Worked example 2 (why the gate is mandatory):* a later fan-out's recon **and** its adversarial-verify
    agent both reasoned from code and **endorsed a "fix"** to `measurement_date` — which a live probe
    against real `+07:00` data then showed would have **corrupted 411,190 rows (29%)**. Two agents
    agreed and were both wrong; only the real-data probe caught it. Confident agreement is not verification.
- Outputs feed PLAN; EXECUTE stays gated on explicit approval.

## Companion docs
Architecture/decisions: `PIPELINE-REPORT.md` · deployed inventory: `DEPLOYED-SPECS-AND-AUDIT.md` ·
data flow/governance: `DATA-LIFECYCLE.md` · scored evaluation: `ARCHITECTURE-EVALUATION.md`.

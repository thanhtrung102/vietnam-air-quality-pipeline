# Research Workflow — project reference

> The reusable research method for this pipeline. It extends the base kit (RIPER-5 RESEARCH +
> deep-research fan-out + adversarial verify) with the lanes a **deployed, regulated-domain data
> pipeline** needs. Use it to open every development cycle. Last updated 2026-05-31.

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
- **EPA AQI breakpoint table must be post-2024** (PM2.5, effective 2024-05-06): 50↔9.0, 100↔35.4,
  150↔55.4, 200↔**125.4**, 300↔**225.4**, 500↔**325.4** µg/m³ (input truncated to 0.1 before lookup).
  (Pre-2024 used 12.0/35.4/55.4/150.4/250.4/350.4/500.4 — wrong.)
  *Status 2026-05-30: CORRECT in `mart_daily_air_quality.sql` + `mart_health_summary.sql`; values
  re-confirmed against EPA fact sheet + Federal Register 2026-05-31. Re-verify bp200=125.4 (not legacy
  150.4) on any change.*
- **Daily AQI = local-midnight (UTC+7) 24-h mean, truncated to 0.1 µg/m³** before breakpoints.
  *Status 2026-05-30: day-window CORRECT — `cast(timestamp-with-tz AS date)` keeps the +07:00 local
  date (verified live: `01:00+07:00` → date `2023-01-01`). Note: `measured_at` is UTC-rebased while
  `measurement_date` is local — harmless for date-grouped daily marts, a trap for any sub-daily logic.*
- **NowCast** (12-h weighted, `w=max(c_min/c_max, 0.5)`) is required for any *"current conditions"*
  view; daily AQI is not a live number.
- **Low-cost sensors (3× AirGradient/PMS5003):** RH over-read at high humidity is real, but **do not
  blind-apply the Barkjohn US PurpleAir coefficients** (`0.524·PA − 0.0862·RH + 5.75`, Barkjohn et al.
  2021, AMT 14:4617) — they're PurpleAir- and US-aerosol-specific. Correct scope = *collocate + fit
  local coefficients*; until then flag low-cost PM2.5 as indicative.
  - **⚠️ OPEN DEFECT (web-verified 2026-05-31):** the deployed `corrected_pm25 = avg /
    (1 + 0.24·RH_fraction)` is attributed to "EPA/Jayaratne" — **this citation is false**. No Jayaratne
    correction of this form exists (Jayaratne 2018, AMT 11:4883, documents the RH over-read but
    publishes no such formula), and the real hygroscopic correction is **nonlinear** (κ-Köhler:
    `PM_dry = PM_wet / (1 + κ/(100/RH − 1))`, diverging as RH→100%) — a linear `(1+0.24·RH)` divisor
    cannot capture it and the `0.24` traces to no source. Direction is defensible, magnitude is
    unvalidated. **Fix:** strip the false citation and relabel as an unvalidated heuristic at minimum;
    ideally replace with a locally-collocated Barkjohn or κ-Köhler fit. Tracked in
    `process/context/domain-data-quality/all-domain-data-quality.md`.
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
  query-based test** in the non-blocking `dbt test` step, backed by the deployed `DaysSinceLastNewMart`
  CloudWatch alarm. **Query the consumer mart, not the raw source, and return a partition-key column:**
  `select max(measurement_date) from {{ ref('mart_daily_aqi') }} having max(measurement_date) <
  date_add('day', -N, current_date)`. Two live-verified traps, each caught only by running on real
  data (a code-read would miss both): (1) scanning the raw partition-projected CSV source has no
  pruning and is slow/costly — querying the date-partitioned Parquet mart prunes to metadata
  (*correction, verified live 2026-05-31:* at the current ~1.4 M-row volume a raw `max(datetime)`
  probe actually scanned only ~10 MB, so the raw scan is not yet prohibitive — but the mart-query
  approach is still preferred because it returns a `date` for trap 2 and stays cheap as history
  grows; don't repeat the earlier overstated "blows the 10 GB cap" claim); (2) dbt
  `--store-failures` CTAS-es the test result, and a `timestamp with time zone` column (e.g. from
  `from_iso8601_timestamp`) throws `NOT_SUPPORTED: Unsupported Hive type: timestamp(3) with time zone`
  — returning a `date` is storable. A stalled source still surfaces because the mart stops gaining
  days even on a green rebuild. Still enforce `contract: {enforced: true}` on the consumer marts
  (`mart_daily_aqi`, `mart_daily_air_quality`).
  - **Calibrate the threshold to the deployed alarm, not to a guess (verified live 2026-05-31).** The
    `N` above must equal the deployed `DaysSinceLastNewMart` alarm threshold so the test and the alarm
    cannot disagree — that alarm is the canonical freshness SLA. The alarm is **21 days**; an earlier
    test used **3 days**, which (a) contradicted the alarm 7×, and (b) false-fires on normal operation
    — the OpenAQ archive lag runs up to ~10 days behind wall-clock when healthy (PIPELINE-REPORT §6),
    and a live probe found `mart_daily_aqi` exactly 3 days behind, i.e. *on the 3-day boundary while
    perfectly healthy*. A too-tight freshness threshold reintroduces the same constant-WARN masking
    this lane exists to kill. Set N = alarm threshold; re-derive N if the alarm changes.
  - **One freshness test per *consumed* source, threshold matched to that source's own lag.** Add the
    test only where a default-built mart depends on the source (a dbt test protects a downstream
    consumer; a source nothing `ref`s has nothing to protect). Worked example 2026-05-31: `batch` →
    `mart_daily_aqi` (21 d, matches alarm); `weather` → `mart_daily_weather`→`mart_aq_weather_daily`→
    `mart_lagged_features` (7 d — Open-Meteo ERA5T lag is shorter; weather mart was only 1 day behind
    vs the AQI mart's 3); `stream` → **no mart consumes it**, and the daily 02:30 dbt run is the wrong
    cadence to watch a 30-min stream, so it is monitored in CloudWatch (iterator-age / DLQ-depth /
    producer-errors) and gets **no** dbt freshness test. Don't add a hollow test to a source with no
    consumer just for symmetry — say so in `sources.yml` and name the real monitor.
- **Idempotent backfill** = partition overwrite: marts are `partitioned_by=['measurement_date']`, so
  `incremental` + `insert_overwrite` keyed on date is the cheapest idempotent path **when** full-refresh
  scan cost justifies it (not before). Iceberg `merge` + Write-Audit-Publish only if row-level
  upserts/corrections become a requirement.
- **Data observability ≠ infra observability:** a green job can still produce wrong/stale/half-loaded
  data. Watch freshness, volume, distribution, schema, lineage — not just Lambda errors.

### Lane 5 — Constraint envelope (the adversarial filter) **[always]**
Every recommendation must pass: **≤ ~$3–8/mo · single operator · serverless/scale-to-zero ·
QuickSight Standard (BI gated) · ~5 actively-reporting stations · remote S3 Terraform state (no DynamoDB).**
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

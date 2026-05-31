# Transform (dbt-on-Athena) — Context Group

Last updated: 2026-05-31. Router for the dbt project. **Highest data-correctness blast radius.**
Parent: `process/context/all-context.md`.

## Scope

dbt project `openaq_transform` (adapter `dbt-athena-community`): staging → intermediate → marts, seeds,
singular tests, source-freshness gates, the Glue external tables it reads. CodeBuild runner.

## Read when

Touching any dbt model, seed, test, source definition, the freshness gates, the Glue raw tables, or the
CodeBuild build pipeline.

## Quick facts

- **Layout:** `models/staging/` (stg_measurements, stg_weather + sources.yml, schema.yml) →
  `models/intermediate/` (int_measurements_enriched, int_weather_enriched) → `models/marts/` (15 marts).
  `seeds/` = `vn_stations.csv` (21-station allowlist, source of truth) + `vn_holidays.csv` (61).
- **Materialization:** marts are Parquet/Snappy CTAS to `processed/openaq_mart/{table}/{uuid}/`.
  Date-grain marts `partitioned_by=['measurement_date']`; `mart_forecast_accuracy` on `forecast_date`;
  aggregate marts unpartitioned.
- **`bi_disabled` tag** excludes 8 marts (QuickSight-only / forecast-dependent) from the default build:
  `dbt build --exclude tag:bi_disabled` builds 12 of 20.
- **Station allowlist** = inner-join to `vn_stations` seed at the intermediate layer.
- **DQ filter:** `-999.0` sentinel dropped; pm25-only `value >= 500` fill-code guard (station 7440 emits
  985.0), **not** applied to pm10 (legit coarse-dust spikes survive).

## Freshness gating (Athena-specific — STILL required in 2026)

- **Do NOT use `dbt source freshness` on Athena.** dbt-athena computes it from Glue `last_modified`
  returned as a string → errors on every source. **Verified still-open May 2026:**
  dbt-labs/dbt-adapters #426 (successor to dbt-athena #631). The query-based singular-test workaround
  remains necessary.
- **Pattern:** query the consumer **mart** (Parquet, date-partitioned → metadata-pruned, near-zero
  scan) and return a `date` (storable by `--store-failures`; a `timestamp with time zone` is not).
  - `tests/assert_batch_source_fresh.sql` — 21 days, **matched to the deployed `DaysSinceLastNewMart`
    alarm** (the canonical SLA — calibrate the test to the deployed control, never to a guess).
  - `tests/assert_weather_source_fresh.sql` — 7 days (Open-Meteo lag shorter than OpenAQ archive).
  - `stream` has **no dbt consumer** → monitored in CloudWatch, not dbt (no hollow test).
- Also `tests/assert_composite_aqi_is_source_max.sql`, `assert_health_category_matches_composite_aqi.sql`.

## Source docs

- Data flow + DQ gates: `docs/DATA-LIFECYCLE.md` §3, §7
- Design rationale: `docs/PIPELINE-REPORT.md` "Transform (dbt)"
- Data-eng rigor + freshness method: `docs/RESEARCH-WORKFLOW.md` Lane 4
- Build-from-scratch: `docs/workshop/5.5-transform-security.md`

## Source code

Entire `transform/` (models, seeds, tests, `buildspec_dbt.yml`, `dbt_project.yml`, `sources.yml`),
`terraform/glue_tables.tf` (raw external tables with partition projection).

## Known issues / open questions

- **Table format:** confirm Hive/Parquet vs Iceberg in source config — it changes the freshness query
  (Iceberg min/max ignores metadata and full-scans; Hive prunes by partition).
- `dbt parse` cannot run on the current host (Python 3.14 / mashumaro incompatibility) — validate test
  SQL via live Athena dry-runs; CI `validate.yml` is the machine-check on push.
- AQI-macro / `int_city_daily_pm25` refactor was extracted then **removed as dead code** (inline AQI
  logic kept deliberately). No `macros/` dir.
- **Domain-correctness defect in a mart:** see `domain-data-quality/all-domain-data-quality.md`
  (`corrected_pm25` mis-cited formula).

## Update triggers

New/changed model, seed, test, source; freshness threshold change (re-derive from the deployed alarm);
Glue table change. After change: `dbt build` on CodeBuild green + live Athena verification.

# Data Quality & Test Strategy

How the transform layer is tested, why each layer exists, and how to run it. This is the
data-engineering-rigor (Lane 4 of `RESEARCH-WORKFLOW.md`) reference for the project. The serving
Lambdas are covered separately by `pytest` (`lambda/tests/`); this doc is the **dbt** test strategy.

> Source of truth is the test code (`transform/models/**/*.yml`, `transform/tests/`) and a live
> Athena run via the `openaq-dbt-runner` CodeBuild project. This doc explains the layers.

## The five test layers

| Layer | Where | Catches | Cost |
|---|---|---|---|
| **Generic tests** | `models/**/schema.yml` | nulls, broken keys, out-of-set categories, duplicate grain, out-of-range values | small Athena scan per test |
| **Singular tests** | `tests/*.sql` | hand-written domain invariants + source freshness | small Athena scan |
| **Unit tests** | `models/marts/unit_tests.yml` | wrong *transformation logic* (AQI math, tie-break) on mocked inputs | ~0 (inline `VALUES`) |
| **Distributional / cross-column** | `models/**/schema.yml` (dbt-expectations) | empty builds, `max ≥ avg ≥ min` violations, physical impossibilities | small Athena scan |
| **Operational freshness** | CloudWatch alarm `DaysSinceLastNewMart` (21d) | stale marts at runtime (independent of a dbt run) | n/a (metric) |

The layering is deliberate: generic tests assert *shape*, singular tests assert *domain rules*,
unit tests assert *logic* (and uniquely run without any real data), expectations assert
*distributional sanity*, and the CloudWatch alarm catches staleness even when no dbt run happens.

### 1. Generic tests (`schema.yml`)
`not_null`, `unique`, `accepted_values`, `relationships`, plus `dbt_utils.unique_combination_of_columns`
and `dbt_utils.accepted_range`. These enforce the grain (e.g. one row per `measurement_date ×
location_id`), the station allowlist (`relationships` to the `vn_stations` seed), the EPA AQI 0–500
range, and the fixed category vocabulary on every consumer mart.

### 2. Singular tests (`tests/`)
Four hand-written SQL assertions (each returns offending rows; empty = pass):
- `assert_batch_source_fresh.sql` / `assert_weather_source_fresh.sql` — query-based source freshness
  (batch ≤ 21 days, weather ≤ 7 days). Used instead of `dbt source freshness` because dbt-athena
  computes freshness from Glue `last_modified` as a string and errors on every source (dbt-athena #631).
  The 21-day batch threshold is kept in lock-step with the `DaysSinceLastNewMart` CloudWatch alarm.
- `assert_composite_aqi_is_source_max.sql` — `mart_daily_aqi.composite_aqi` must equal the max
  per-pollutant AQI from `mart_daily_air_quality` (guards the composite join-back against drift).
- `assert_health_category_matches_composite_aqi.sql` — the health category label must match the
  composite AQI band.

### 3. Unit tests (`models/marts/unit_tests.yml`) — logic, no data
dbt unit tests mock every `ref()` with literal rows and assert the model's output, so they test the
**business logic in isolation** and scan ~0 bytes. Two are defined:
- `test_pm25_pm10_aqi_breakpoints` (on `mart_daily_air_quality`) — pins the US EPA 2024 AQI
  piecewise-linear interpolation for PM2.5 and PM10 at category boundaries + a mid-bucket value, and
  asserts non-PM parameters get a NULL AQI. If anyone edits a breakpoint constant, this fails.
- `test_composite_aqi_and_pm25_tiebreak` (on `mart_daily_aqi`) — pins composite-AQI = worst pollutant
  and the PM2.5-wins tie-break for `dominant_pollutant` / `health_category`.

### 4. Distributional & cross-column (dbt-expectations)
`calogica/dbt_expectations` (in `packages.yml`) adds assertions the generic layer can't express:
- `expect_table_row_count_to_be_between` (min 1) on `mart_daily_air_quality` and `mart_daily_aqi` —
  catches a silently **empty** build (the column tests pass vacuously on zero rows).
- `expect_column_pair_values_A_to_be_greater_than_B` — the daily aggregate invariant
  `max_value ≥ avg_value ≥ min_value`.
- `expect_column_values_to_be_between` on `pm25_avg` (0–500) — physical non-negativity + the staging
  ceiling.

### 5. Operational freshness (CloudWatch)
The `completeness_check` Lambda emits `DaysSinceLastNewMart`; an alarm fires at 21 days. This is the
runtime backstop — it catches staleness even on days the scheduled dbt run is skipped or fails.

## Deliberately deferred (with rationale)

- **Enforced model contracts** (`contract: {enforced: true}`) — Athena requires exact per-column
  `data_type` declarations and is brittle to type-name drift (varchar/double/integer/date); high
  build-churn for little gain on a single-operator demo. Revisit if an external consumer freezes on
  a schema.
- **Elementary** observability — materialises its own models + an artifacts schema → recurring Athena
  tables/scan cost, out of the scale-to-zero envelope. The CloudWatch freshness alarm + singular
  freshness tests already cover the anomaly case that matters here.

## How to run

```bash
cd transform
dbt deps                                          # installs dbt_utils + dbt_expectations (+ dbt_date)
dbt parse                                         # offline compile check (what CI runs)
dbt test                                          # all layers (needs AWS creds + Athena workgroup)
dbt test --select mart_daily_air_quality,mart_daily_aqi   # the unit-tested models
```

Tests run automatically in the `openaq-dbt-runner` CodeBuild `post_build` step (`dbt test
--store-failures`, non-blocking) after the daily `dbt run`. **Deploy note:** editing dbt files and
pushing does NOT deploy them — `terraform apply` re-packages `codebuild-source.zip` from `transform/`;
the next scheduled (or manually started) build then picks them up.

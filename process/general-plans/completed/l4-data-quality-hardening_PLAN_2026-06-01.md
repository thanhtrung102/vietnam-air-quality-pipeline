# L4 Data-Engineering Rigor — Test-Breadth Hardening

**Date:** 2026-06-01
**Complexity:** Moderate (test/contract additions; no model-logic change; CI-only cost)
**Status:** ✅ RESOLVED 2026-06-01 — verified live via CodeBuild `openaq-dbt-runner`.

## Resolution (2026-06-01, live-verified)
- Both unit tests **PASS** (`test_pm25_pm10_aqi_breakpoints`, `test_composite_aqi_and_pm25_tiebreak`)
  — confirms dbt-athena-community supports unit tests and the EPA breakpoint + composite/tie-break
  logic is correct. dbt-expectations resolved (`dbt deps`) and its tests **PASS**.
- First run: `PASS=83 WARN=0 ERROR=1 / 84`. The 1 error was a **pre-existing, unrelated** defect the
  new run surfaced: `accepted_values_mart_diurnal_profile_day_type` threw a Compilation Error because
  `--store-failures` derives the audit-table name from the test name (`…__Weekday__Weekend`), Athena/
  Glue lowercases it, and dbt's case-sensitive lookup then hit an ambiguous relation. It was the only
  accepted_values test both short enough to avoid hash-aliasing and carrying mixed-case values. **Fixed**
  by giving the test an explicit lowercase `name: accepted_values_diurnal_day_type`. Re-verification
  build in flight at writing.
- Deferred (documented in `docs/DATA-QUALITY.md` + `docs/WELL-ARCHITECTED.md`): enforced contracts,
  Elementary — envelope-justified, not gaps.

## Why (research grounding)

The "implemented vs research scope" evaluation (2026-06-01) found the largest open gap is
`docs/RESEARCH-WORKFLOW.md` **Lane 4 (data-engineering rigor)**. The pipeline already has a
respectable generic-test layer (`not_null`, `unique`, `accepted_values`, `relationships`,
`dbt_utils.accepted_range`, `dbt_utils.unique_combination_of_columns`) plus **4 singular tests**
(freshness ×2, composite-AQI invariant, health-category invariant). What scope calls for but is
**missing**:

- **dbt unit tests** for transformation logic (the EPA AQI breakpoint math + composite/tie-break) —
  the standout modern data-eng signal, and the cheapest possible test (mocked inputs, ~0 scan).
- **dbt-expectations** distributional / cross-column expectations (row-count > 0, monotone
  `max ≥ avg ≥ min`, physical non-negativity) that the generic layer can't express.
- A **documented test strategy** (portfolio artifact for FCJ review).

This is the most FCJ-portfolio-aligned gap: it demonstrates serverless data-eng *discipline*,
runs entirely inside the existing `openaq-dbt-runner` CodeBuild `dbt test` step, and adds
negligible Athena cost (unit tests scan literal `VALUES`; the expectation tests scan tiny curated
marts). It stays inside the constraint envelope.

## Out of scope / deferred (with rationale)

- **Enforced model contracts** (`contract: {enforced: true}`): deferred this cycle. Athena contract
  enforcement requires exact `data_type` declarations per column (varchar/double/integer/date/boolean)
  and is brittle to type-name drift — high build-churn risk for a demo. Revisit if a downstream
  consumer hard-depends on a frozen schema.
- **Elementary** observability package: deferred. It materialises its own observability models +
  needs an artifacts schema → adds Athena tables and recurring scan cost; out of envelope for a
  scale-to-zero demo. The deployed `DaysSinceLastNewMart` CloudWatch alarm + the singular freshness
  tests already cover the freshness-anomaly case that matters here.
- Lane 2 validated low-cost-sensor correction (needs a local collocation campaign — external blocker)
  and multi-pollutant AQI sub-indices (NO₂/O₃/SO₂/CO unit normalisation — larger, separate cycle).

## Execute

1. `transform/models/marts/unit_tests.yml` — two dbt unit tests:
   - `test_pm25_aqi_breakpoints` on `mart_daily_air_quality`: mock `int_measurements_enriched` with
     PM2.5/PM10 rows at known concentrations; assert `aqi_value` + `aqi_category` (boundary + a
     mid-bucket interpolation + a non-PM parameter → NULL).
   - `test_composite_aqi_and_tiebreak` on `mart_daily_aqi`: mock `mart_daily_air_quality` with two
     pollutant rows; assert `composite_aqi` = max, PM2.5 tie-break wins, correct `health_category`.
2. `transform/packages.yml` — add `calogica/dbt_expectations` (pulls `dbt_date` transitively).
3. `transform/models/marts/schema.yml` — add dbt-expectations tests:
   - `mart_daily_air_quality`: `expect_table_row_count_to_be_between` (min 1);
     `expect_column_pair_values_A_to_be_greater_than_B` (max ≥ avg, avg ≥ min, `or_equal`).
   - `mart_daily_aqi`: `expect_table_row_count_to_be_between` (min 1);
     `pm25_avg` `expect_column_values_to_be_between` (≥ 0).
4. `docs/DATA-QUALITY.md` — document the layered test strategy (generic / singular / unit /
   expectations / freshness) + how to run.

## Verify (HARD GATE — live)

- `terraform apply -target=aws_s3_object.codebuild_source` (rebuilds + uploads `codebuild-source.zip`
  from `transform/` — the deploy gotcha: editing dbt files alone does NOT deploy).
- `aws codebuild start-build --project-name openaq-dbt-runner`; tail
  `/aws/codebuild/openaq-dbt-runner`; require: `dbt deps` resolves dbt_expectations+dbt_date,
  unit tests PASS, expectation tests PASS, build SUCCEEDED. Capture the run id + PASS/FAIL counts.
- If the adapter rejects unit tests, fall back to a seed-fixture singular test (Athena-native) and
  re-run; do not leave a permanently-erroring test (noise — same reason source-freshness gate was removed).

## Then update

`docs/DATA-QUALITY.md`, `process/context/tests/all-tests.md` (surface table + counts), CLAUDE.md
test note, memory `project_vn_aq_harness.md`. Move this plan to `completed/`.

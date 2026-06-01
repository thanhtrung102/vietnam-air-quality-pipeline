# Tests — Context Group Entry Point

Quick router for **how this project is tested and verified**. This is the `tests/` context group
entrypoint (`process/context/tests/all-tests.md`). Read it before deeper test work, debugging, or
when a plan needs verification gates. Loaded by RIPER-5 agents whenever a task touches testing,
verification, or debugging.

> Source of truth is the test code itself (`lambda/tests/`, `transform/tests/`) and a live AWS probe.
> This doc routes; it does not replace running the suite.

---

## Test Surfaces

| Surface | Location | What it covers | Runner |
|---|---|---|---|
| Lambda unit tests | `lambda/tests/` | the 5+1 Lambda handlers: batch_sync, streaming, weather_ingest, aqi_api, completeness_check, forecast_generate; plus `lambda/shared/` helpers | `pytest` |
| dbt singular tests | `transform/tests/` | 4 hand-written SQL assertions (freshness ×2, composite-AQI invariant, health-category invariant) | `dbt test` |
| dbt generic tests | `transform/models/**/*.yml` schema tests | `not_null`, `unique`, `accepted_values`, relationships, `dbt_utils.accepted_range`/`unique_combination_of_columns` on staging/intermediate/marts | `dbt test` |
| dbt **unit tests** | `transform/models/marts/unit_tests.yml` | transformation *logic* on mocked inputs (~0 scan): EPA AQI breakpoint math; composite-AQI + PM2.5 tie-break | `dbt test` |
| dbt **expectations** | `transform/models/marts/schema.yml` (dbt-expectations) | empty-build guard (row-count ≥ 1); `max ≥ avg ≥ min`; `pm25_avg` non-negativity | `dbt test` |
| CI gate | `.github/workflows/validate.yml` | `terraform fmt -check` + `validate`, `pytest`, `dbt parse` on every push/PR | GitHub Actions |

Full dbt test strategy (the five layers + deferred items): `docs/DATA-QUALITY.md`.

Headline state (re-run live 2026-05-31): **85 Lambda unit tests pass / 0 fail** (`pytest lambda/tests`,
2.95s). Keep this number current when tests are added — it is also cited in `README.md`. Note: `pytest`
+ `moto` are dev-only deps (not in `requirements.txt`); `pip install pytest moto` before running locally.

---

## How To Run

```bash
# Lambda unit tests (from repo root; uses .venv)
python -m pytest lambda/tests -q

# dbt tests (requires AWS creds + the openaq Athena workgroup; from transform/)
cd transform && dbt test            # all generic + singular tests
dbt test --select mart_daily_aqi    # scope to one model
dbt parse                           # fast compile-only check (what CI runs)
```

dbt tests issue real Athena queries — they cost scan bytes and need live credentials. `dbt parse`
is the cheap, offline-safe gate; prefer it for quick validation and let CI/manual runs do `dbt test`.

---

## Verification Gates (use these when writing a plan)

A data-pipeline change is **not done** until the relevant gate below is green and the evidence is
captured (per the live-state-verification HARD GATE in
`process/development-protocols/live-state-verification.md`):

- **Lambda logic change** → `pytest lambda/tests` green + the touched handler's test updated.
- **dbt model/mart change** → `dbt parse` + `dbt test --select <model>+` green; row-count delta on the
  affected mart probed against live Athena (not inferred from SQL).
- **Freshness/SLA change** → confirm the `DaysSinceLastNewMart` alarm threshold (21d) and the dbt
  freshness test stay aligned — see `transform-dbt/all-transform-dbt.md`.
- **Infra/Terraform change** → `terraform validate` + `terraform plan` reviewed; no unintended
  resource replacement.
- **Serving/API change** → hit the deployed API Gateway URL and assert GeoJSON/CORS shape live.

---

## Debugging Entry Points

When a test or pipeline run fails, use the `vc-debug` skill (systematic root-cause methodology) and
capture pre-fix evidence (exact error, failing command + full output, relevant log lines). For
Athena/dbt failures, read `transform-dbt/all-transform-dbt.md`; for ingestion failures read
`ingestion-lambdas/all-ingestion-lambdas.md`; for alarms/ops read `deployment-ops/all-deployment-ops.md`.

---

## Related Context

- Transform/dbt internals and the freshness gate: `transform-dbt/all-transform-dbt.md`
- Ingestion Lambda behavior: `ingestion-lambdas/all-ingestion-lambdas.md`
- CI/monitoring/alarms: `deployment-ops/all-deployment-ops.md`
- Root router: `process/context/all-context.md`

# Backlog — Lambda micro-cleanups (low value; need a pytest re-run to land safely)

Surfaced by the Phase 06 codebase inspection. None affect runtime correctness; deferred to avoid
unverified edits to shared Lambda code without re-running `pytest lambda/tests` (85 tests).

- **Unused imports:** `lambda/shared/athena_utils.py` (`field` from dataclasses); `lambda/tests/test_aqi_api.py` (`call`); `lambda/tests/test_forecast_generate.py` (`call`, `ANY`). → remove.
- **`lambda/weather_ingest/handler.py:189`** — the completion log passes `len(STATIONS)` for **both** `stations=` and `requests=`; the `requests=` metric is therefore wrong. → track a real request counter.
- **print vs logging** — batch_sync/streaming/completeness use `print()`; weather/forecast use `logging`. → standardize on `logging`.
- **Station-roster fallback duplication** — `_DEFAULT_STATION_IDS` hardcoded in `batch_sync` + `streaming/kinesis_producer` (+ `weather_ingest` coords). These are *fallback defaults*; runtime values are Terraform-injected from the `vn_stations` seed. → optional: move defaults to `lambda/shared/`.

**To land:** make the edits, run `pip install pytest moto && python -m pytest lambda/tests -q` green, then commit as an execution change.

# Fix the SARIMA Forecast Subsystem (Forecast Monitor — 4th dashboard sheet)

**Date:** 2026-06-01
**Complexity:** Complex (container build + ML model code + sparse-data handling)
**Status:** ✅ RESOLVED 2026-06-01 — SARIMA forecast LIVE; Forecast Monitor (4th sheet) deployed.

## Resolution (2026-06-01)
- **Defect #4 (SARIMA model) FIXED:** modelled on a positional RangeIndex (not the gappy
  DatetimeIndex); append a 1-D numpy array in the walk-forward; made the backtest exception-safe.
  Live result: `stations_ok=17, errors=0, sarima_records=35` (5 active stations × 7 days), avg holdout
  RMSE 17.7 µg/m³, forecast 2026-05-29→06-05. `mart_daily_forecast` populated; `GET /analytics/forecast`
  serves 35 rows; the dashboard **Forecast Monitor** sheet renders.
- **Defects #1–#3 FIXED** (container packaging + build wiring) as recorded below; the image is built via
  CodeBuild `openaq-forecast-image` and the forecast Lambda/schedule/alarm are deployed (image URI
  persisted in `terraform/terraform.tfvars`).
- **Remaining minor (only matters when forecast *code* changes):** the `openaq-forecast-image` CodeBuild
  project is NOT in Terraform and its source is `codebuild-source.zip` (dbt-only). Each image rebuild
  currently needs the combined-zip step (append `lambda/forecast_generate/` + `lambda/shared/` into that
  key). Permanent fix: bring the project into Terraform with its own source archive + role grant. The
  daily forecast does NOT rebuild the image, so this does not affect ongoing operation.


## Why this is here

While enabling the gated SARIMA forecast to power the **Forecast Monitor** (the 4th sheet of the
QuickSight alternative — see `completed/quicksight-alternative-analytics-dashboard_PLAN_2026-06-01.md`),
the gated forecast path turned out to have **four latent defects**. Three are now **fixed**; the fourth
is a genuine ML/data bug that needs a focused effort. The 6 forecast resources were **rolled back** so
the live stack stays at the verified 3-sheet state.

## Defects found (live, 2026-06-01)

1. **✅ FIXED — CodeBuild image source mis-wired.** `openaq-forecast-image` project pulls
   `s3://…/codebuild-source.zip`, but that zip is built by Terraform `archive_file` from `transform/`
   only — so it lacks `lambda/forecast_generate/buildspec.yml`. *Permanent fix needed:* make the
   Terraform `codebuild_source` archive include `lambda/forecast_generate/` + `lambda/shared/`, or give
   the project its own source. (Worked around this round by appending those into the zip out-of-band.)
2. **✅ FIXED — CodeBuild role S3 scope.** `codebuild-openaq-role` allows `s3:GetObject` only on the
   `codebuild-source.zip` key, so a separate source key 403s. (Worked around by reusing that key.)
3. **✅ FIXED (committed) — container missing `athena_utils`.** `Dockerfile` only `COPY handler.py`;
   `handler.py` does `from athena_utils import …` → `Runtime.ImportModuleError`. Fixed: `Dockerfile`
   now `COPY athena_utils.py .` and `buildspec.yml` stages it from `../shared/` before `docker build`.
4. **⏳ OPEN — SARIMA model code bug + sparse data.** After the image ran, the Lambda returned
   `stations_ok:12, errors:5, sarima_records:0` (zero forecasts written). Root cause from logs:
   - `_walk_forward_rmse(pm25_ser, HOLDOUT_DAYS)` raises **`ValueError: Given 'endog' does not have an
     index that extends the index of the model`** — statsmodels SARIMAX `.append/.extend` fails because
     the PM2.5 series' DatetimeIndex has **no frequency** (`ValueWarning: A date index has been provided
     but it has no associated frequency`). Irregular/gappy daily station data → no inferable freq.
   - Sparse stations are skipped (`Station 2161316: only 28 rows — skipping`).

## What to do (open item #4)

In `lambda/forecast_generate/handler.py`:
- Give the series a real daily frequency before fitting: build a continuous `pd.date_range` daily index,
  reindex, and handle gaps (interpolate small gaps / drop stations below a minimum span), so SARIMAX and
  the walk-forward `.append` align. OR switch SARIMAX to an integer step index (forecast by step, not
  date) and attach dates afterward.
- Decide a minimum-history threshold; with only ~5 actively-reporting stations and multi-day archive
  lag, forecast only stations that clear it, and surface "insufficient data" cleanly.
- Re-test: `aws codebuild start-build --project-name openaq-forecast-image` (after the #1 permanent fix),
  `update-function-code`, invoke → expect `sarima_records > 0`; then query `mart_daily_forecast`.

## Then finish the 4th sheet (already scaffolded)

- `lambda/aqi_api/analytics.py` already has the `forecast` dataset (`GET /analytics/forecast`, latest
  `generated_at` partition). Deploy the rebuilt `aqi_api` and add a **Forecast Monitor** sheet to
  `dashboard/index.html` (7-day line per station + 95% CI band + holdout-RMSE KPI).
- `mart_daily_forecast` Athena external table is **already registered** (empty) from this round.

## Constraint-envelope note
All in-envelope (ECR ≈ $0.15/mo, forecast Lambda within free tier). The blocker is correctness, not cost.

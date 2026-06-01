# Serving (API + Dashboard) — Context Group

Last updated: 2026-05-31. Router for the serving layer. Parent: `process/context/all-context.md`.

## Scope

`aqi_api` Lambda, API Gateway (HTTP, GeoJSON/CORS), the Leaflet static dashboard.

## Read when

Touching the API handler, the GeoJSON contract, API Gateway config, throttling, or the dashboard.

## Quick facts

- **`openaq_aqi_api`** behind API Gateway `GET /` → GeoJSON FeatureCollection from `mart_daily_aqi`.
  Filters to **last 7 days, latest row per station** (partition-pruned → small scan; tolerates ~6 days
  archive lag). Returns valid-but-empty GeoJSON when the archive lag exceeds the window (normal).
- **Analytics endpoints (QuickSight alternative, 2026-06-01):** same Lambda also serves
  `GET /analytics/{dataset}` → JSON. `handler.py` routes on `requestContext.http.path`; queries live in
  `lambda/aqi_api/analytics.py` (packaged by `build.sh`). Datasets: `health` (mart_health_summary),
  `seasonal` (mart_monthly_profile + mart_diurnal_profile), `compliance` (mart_exceedance_stats). Each
  /tmp-cached per dataset+day. Consumed by the dashboard **Analytics tab** (Chart.js, 3 sheets). The 4
  backing marts were un-`bi_disabled` for this. Forecast Monitor (4th QuickSight sheet) still deferred
  (SARIMA gated).
- **API Gateway throttling:** burst 20 / rate 10, reserved Lambda concurrency 10 (cost/abuse guard).
- **Dashboard** = `dashboard/index.html` (Leaflet) on S3 static website. The real API URL is injected
  by Terraform (`aws_s3_object.dashboard_index` + `templatefile`/`replace`) — `index.html` reads
  `window.AQI_API_URL || "YOUR_API_GATEWAY_URL"`. No manual edit step.
- `dashboard/serve.py` + `demo_data.json` are **local-dev only** (demo_data.json is gitignored/stale —
  not a serving dependency).

## Source docs

- Serving design: `docs/PIPELINE-REPORT.md` "Serving"
- Data flow §4: `docs/DATA-LIFECYCLE.md`
- Build-from-scratch (dashboards): `docs/workshop/5.5-transform-security.md`

## Source code

`lambda/aqi_api/handler.py`, API Gateway in `terraform/lambda.tf`, `dashboard/`.

## Known issues

- Empty GeoJSON during normal archive lag is expected — don't mistake it for an outage (cross-check
  `mart_daily_aqi` freshness, not the API response, to judge staleness).

## Update triggers

GeoJSON contract change, API Gateway/throttle change, dashboard rework. Verify live (`aws lambda
invoke openaq_aqi_api`, HTTP 200 + valid GeoJSON) after change.

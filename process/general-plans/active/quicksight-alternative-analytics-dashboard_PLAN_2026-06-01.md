# QuickSight Alternative — Static Analytics Dashboard (3-sheet MVP)

**Date:** 2026-06-01
**Complexity:** Complex (touches marts + serving Lambda + API Gateway + frontend; correctness-relevant)
**Status:** Active — EXECUTE in progress
**Owner decision (INNOVATE gate, 2026-06-01):** Approach **A** (extend the static S3 dashboard), scope
**3-sheet MVP on live data** (Health Scorecard · Seasonal & Weather Drivers · Compliance & Trajectory).
Forecast Monitor deferred (SARIMA ML still gated off).

---

## Problem

QuickSight (the designed BI layer) is gated off — it needs Enterprise (~$18/mo), out of the ~$3–8/mo
envelope. The 8 analytical marts that fed its 4 sheets are tagged `bi_disabled` and not refreshed. We
need an in-envelope BI surface that reuses those marts.

## Approach (chosen)

Extend the **existing** serverless serving layer — no new infra category:
- Re-enable the analytical marts so the daily CodeBuild dbt run materializes them.
- Add read-only JSON endpoints to the **existing** `openaq_aqi_api` Lambda (reuses its IAM role,
  Athena access, caching pattern), exposed via **new API Gateway routes** to the same integration.
- Add an **Analytics tab** to the existing Leaflet `dashboard/index.html` rendering the 3 sheets with
  client-side Chart.js (CDN), fed by those endpoints.

Cost ≈ $0 (S3 + Lambda free tier + tiny partition-pruned Athena scans). Scale-to-zero preserved.

## Constraint-envelope check (RESEARCH-WORKFLOW Lane 5)

≤$3–8/mo ✅ (no new persistent compute) · single operator ✅ · serverless/scale-to-zero ✅ ·
QuickSight Standard untouched ✅ · reuses existing S3/API GW/Lambda/Athena/dbt ✅. PASS.

## Data sources (marts to re-enable; columns verified 2026-06-01)

| Sheet | Mart(s) | Grain | Key columns used |
|---|---|---|---|
| Health Scorecard | `mart_health_summary` | city × year | who_compliance_pct, avg_pm25, avg_cigarette_equivalent, {good,moderate,usg,unhealthy,very_unhealthy,hazardous}_days, risk_label |
| Seasonal & Weather Drivers | `mart_monthly_profile`, `mart_diurnal_profile` | loc × param × month / × hour × day_type | month_of_year, hour_of_day, day_type, avg_value (param='pm25', city-aggregated) |
| Compliance & Trajectory | `mart_exceedance_stats`, `mart_annual_monthly_trend` | city × param × year × month | who_exceedance_rate, qcvn_exceedance_rate, p95_pm25, avg_pm25 |

## Public contracts (new)

- `GET /analytics/health`     → `{ "rows": [ {city,year,who_compliance_pct,avg_pm25,...day-counts,risk_label} ] }`
- `GET /analytics/seasonal`   → `{ "monthly": [ {city,month_of_year,avg_pm25} ], "diurnal": [ {city,hour_of_day,day_type,avg_pm25} ] }`
- `GET /analytics/compliance` → `{ "monthly": [ {city,year,month_of_year,who_exceedance_rate,qcvn_exceedance_rate,p95_pm25} ] }`

All JSON, `Access-Control-Allow-Origin: *`, 1 h `/tmp` cache keyed per dataset+UTC-day. Existing
`GET /` GeoJSON map contract **unchanged** (no regression).

## Phases

### Phase 1 — dbt: re-enable marts
Remove `tags = ['bi_disabled']` from the 5 marts above. Default build goes 9 → 14 models.
**Verify:** `dbt ls --exclude tag:bi_disabled --resource-type model` lists the 5 newly-included marts
(total 14); `dbt parse` clean.

### Phase 2 — serving: analytics endpoints
Add `lambda/aqi_api/analytics.py` (3 parameterized, partition-bounded queries + dispatcher). Route in
`handler.py` on `event.requestContext.http.path`: `/` → existing map; `/analytics/{dataset}` →
analytics JSON. Add `analytics.py` to the aqi_api zip in `lambda/build.sh`.
**Verify:** `python -c "import handler, analytics"` imports clean; `bash lambda/build.sh` includes
`analytics.py` in `aqi_api.zip`.

### Phase 3 — infra: API Gateway route
Add `aws_apigatewayv2_route "aqi_api_analytics"` (`GET /analytics/{dataset}`) → existing integration.
Lambda permission `/*` already covers it.
**Verify:** `terraform validate` ✅; `terraform plan` shows +1 route, 0 destroy.

### Phase 4 — frontend: Analytics tab
Add a Map | Analytics tab bar to `dashboard/index.html`; Analytics view with 3 chart blocks
(Chart.js CDN), fetching `${base}/analytics/*` derived from `window.AQI_API_URL`. XSS-escape all
labels (reuse `escHtml`). Map view unchanged.
**Verify:** local open renders without console errors against a stub; headless screenshot after deploy.

### --- PAUSE GATE: live deploy (outward, hard-to-reverse) ---
Code committed + locally verified BEFORE any live mutation. Deploy is a separate approved step:
`build.sh` → `terraform apply` (re-uploads codebuild-source.zip per the deployment gotcha + adds route
+ redeploys Lambda + uploads index.html) → trigger `openaq-dbt-runner` CodeBuild (materialize the 5
marts) → verify endpoints live → headless screenshot.

## Verification evidence (live "done" criteria)
- `curl $API/analytics/health` → HTTP 200, JSON rows for Hanoi + HCMC.
- `curl $API/analytics/seasonal` and `/analytics/compliance` → HTTP 200, populated arrays.
- `aws glue get-table openaq_mart mart_health_summary` etc. → exist + freshly built.
- `curl $API/` → still valid GeoJSON (no map regression).
- Headless screenshot of the Analytics tab rendering all 3 sheets.

## Blast radius / rollback
- **Marts:** additive (un-tag) — re-tagging restores the 9-model build. No schema change to served marts.
- **Lambda:** new paths only; `/` untouched. Revert handler+analytics.py to roll back.
- **API GW:** one additive route; delete to roll back.
- **dbt build cost:** +5 marts ≈ a few extra CodeBuild minutes/day, within envelope.
- No data deletion, no IAM change, no state migration.

## Touchpoints
`transform/models/marts/{mart_health_summary,mart_exceedance_stats,mart_monthly_profile,mart_diurnal_profile,mart_annual_monthly_trend}.sql`,
`lambda/aqi_api/{handler.py,analytics.py}`, `lambda/build.sh`, `terraform/lambda.tf`,
`dashboard/index.html`. Context: `serving-api-dashboard`, `transform-dbt`, `domain-data-quality`.

## Resume
If interrupted: check which phases are committed (`git log`), re-run the phase's Verify step, continue.
EXECUTE order is 1→4 (code, reversible) then the PAUSE GATE deploy.

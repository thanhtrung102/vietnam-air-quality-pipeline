# QuickSight Dashboard Plan — Vietnam Air Quality Pipeline

**Revised 2026-04-09** after domain research on Vietnam air quality policy context,
public health communication best practices, and mart capability audit.

---

## Status Overview

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | IAM — service role + user ARN local | **DONE** (`quicksight_iam.tf`) |
| 2 | Data source + 9 datasets (DIRECT_QUERY, live Athena) | **DONE** (`quicksight_datasource.tf`, `quicksight_datasets.tf`) |
| 3 | Analysis — 4 sheets created via `create_analysis.py` + boto3 | **DONE** (`quicksight_analysis.tf`, `create_analysis.py`) |
| 4 | Published dashboard via template | **DONE** (`quicksight_dashboard.tf`) |
| 5 | Deployment + monitoring | **DONE** |

---

## Why the Dashboard Design Was Revised

The original plan treated the dashboard as an **analyst's view of what the data can show**.
After research into Vietnam's air quality crisis and public health communication literature,
the design was reframed as a **decision-maker's view of a concrete, urgent policy problem**:

- Hanoi PM2.5 averaged **45 µg/m³ in 2024** — 9× the WHO annual guideline of 5 µg/m³
- Vietnam's MAE issued an emergency directive in **November 2025** after Hanoi ranked world's
  most polluted city repeatedly (December 2025, February 2026)
- A **legally binding 2030 target** exists: Hanoi PM2.5 < 40 µg/m³; ≥ 80% Good/Moderate days
- The NE monsoon inversion mechanism (BLH < 500m + calm winds) is the primary driver of
  winter crises — fully captured in `mart_aq_weather_daily` but **absent from the old plan**
- The `cigarette_equivalent` metric (PM2.5 / 22.0) is computed daily in `mart_daily_aqi` but
  was never surfaced as a headline — research shows it is the most effective public health
  communication tool for non-technical audiences

---

## Phase 1 — IAM (DONE)

Files: `terraform/quicksight_iam.tf`

Resources created:
- `aws_iam_role.quicksight_service` — trust policy for `quicksight.amazonaws.com`
- `aws_iam_role_policy.quicksight_service` — Athena (workgroup-scoped), Glue catalog
  (openaq_raw + openaq_mart), S3 read (full bucket) + write (quicksight-staging/ prefix)
- `local.quicksight_user_arn` — derived ARN for `terraform-admin` QuickSight user;
  replaces `aws_quicksight_user` resource (which cannot be imported for pre-existing users)

---

## Phase 2 — Data Source + SPICE Datasets (DONE)

Files: `terraform/quicksight_datasource.tf`, `terraform/quicksight_datasets.tf`

### Athena data source

`aws_quicksight_data_source.athena` — wires QuickSight to `openaq_workgroup` in Athena.
All 9 SPICE datasets share this single data source.

### SPICE datasets (9 total, daily refresh at 04:00 UTC)

All datasets use `import_mode = "SPICE"` and `FULL_REFRESH` daily at 04:00 UTC,
after dbt completes at ~02:45 UTC via CodeBuild scheduler.

| # | Terraform resource | Dataset ID | Mart table | Sheet |
|---|-------------------|-----------|-----------|-------|
| 1 | `aws_quicksight_data_set.daily_aqi` | `openaq-daily-aqi` | `mart_daily_aqi` | 1 |
| 2 | `aws_quicksight_data_set.health_summary` | `openaq-health-summary` | `mart_health_summary` | 1 |
| 3 | `aws_quicksight_data_set.annual_monthly_trend` | `openaq-annual-monthly-trend` | `mart_annual_monthly_trend` | 1 & 3 |
| 4 | `aws_quicksight_data_set.monthly_profile` | `openaq-monthly-profile` | `mart_monthly_profile` | 2 |
| 5 | `aws_quicksight_data_set.diurnal_profile` | `openaq-diurnal-profile` | `mart_diurnal_profile` | 2 |
| 6 | `aws_quicksight_data_set.aq_weather_daily` | `openaq-aq-weather-daily` | `mart_aq_weather_daily` | 2 |
| 7 | `aws_quicksight_data_set.exceedance_stats` | `openaq-exceedance-stats` | `mart_exceedance_stats` | 3 |
| 8 | `aws_quicksight_data_set.pollutant_ratio` | `openaq-pollutant-ratio` | `mart_pollutant_ratio` | 3 |
| 9 | `aws_quicksight_data_set.forecast_accuracy` | `openaq-forecast-accuracy` | `mart_forecast_accuracy` | 4 |

Dataset 6 (`aq_weather_daily`) is new in the revised plan — it is the only dataset that
joins air quality to ERA5 meteorological covariates at daily station grain, enabling the
weather driver analysis on Sheet 2.

---

## Phase 3 — Analysis: 4 Sheets (DONE)

File: `terraform/quicksight_analysis.tf` + `terraform/create_analysis.py`

Phase 3 used a **Python/boto3 workflow** instead of the console because QuickSight visual definitions
(field assignments, axis configs, color rules, reference lines) cannot feasibly be
authored in HCL from scratch. The workflow is:

```
Step 1  terraform apply (Phase 2 already done — 9 datasets exist in SPICE)
Step 2  Build analysis in QuickSight console  →  analysis ID: openaq-air-quality-analysis
Step 3  Export:  aws quicksight describe-analysis-definition \
                   --aws-account-id <account_id> \
                   --analysis-id openaq-air-quality-analysis \
                   --query 'Definition' \
                   > terraform/quicksight_analysis_definition.json
Step 4  Uncomment aws_quicksight_analysis.openaq in quicksight_analysis.tf,
        paste the sheet/visual definitions, then terraform import + terraform apply
```

### Dataset placeholder names (must match what the console creates)

| Placeholder used in definition JSON | SPICE dataset |
|------------------------------------|--------------|
| `daily-aqi` | `aws_quicksight_data_set.daily_aqi` |
| `health-summary` | `aws_quicksight_data_set.health_summary` |
| `annual-monthly-trend` | `aws_quicksight_data_set.annual_monthly_trend` |
| `monthly-profile` | `aws_quicksight_data_set.monthly_profile` |
| `diurnal-profile` | `aws_quicksight_data_set.diurnal_profile` |
| `aq-weather-daily` | `aws_quicksight_data_set.aq_weather_daily` |
| `exceedance-stats` | `aws_quicksight_data_set.exceedance_stats` |
| `pollutant-ratio` | `aws_quicksight_data_set.pollutant_ratio` |
| `forecast-accuracy` | `aws_quicksight_data_set.forecast_accuracy` |

### Sheet 1 — Executive Health Scorecard

**Audience:** City officials, public health directors, media, embassy staff.
**Question:** "At a glance, how dangerous is Hanoi and HCMC air this year vs the 2030 target?"

**Top row — Hero KPIs:**
- Hanoi annual mean PM2.5 (µg/m³) with delta vs prior year
- HCMC annual mean PM2.5 with delta
- **Cigarettes per day equivalent** (`cigarette_equivalent` from `daily_aqi`) — the largest
  number on the page, colour-coded to AQI category. Research shows this is the most effective
  health communication metric for non-technical audiences.
- WHO compliance rate (%) — `who_compliance_pct` from `health_summary`
- Count of Unhealthy+ days (AQI > 150) so far this year vs same period last year

**Row 2 — 2030 Policy Target Gauges** (not in original plan):
- Hanoi PM2.5 gauge: current ~45 µg/m³ → 2030 target 40 µg/m³ (reference line)
  - Calculated field: `(45 - avg_pm25) / (45 - 40) * 100` as % of target reduction achieved
- Good/Moderate day % gauge: `(good_days + moderate_days) / total_days * 100`
  vs 80% target reference line
- Source: `health_summary` calculated fields

**Row 3 — Historical view:**
- AQI calendar heatmap (3-year, 365 days × 3 years): colour = AQI category per day.
  Instantly visualises the NE monsoon red band each November–March.
  Source: `daily_aqi`
- Annual health day stacked bar (city × year): Good / Moderate / USG / Unhealthy /
  Very Unhealthy / Hazardous breakdown. Source: `health_summary`

**Filters:** city (default: all), year range

---

### Sheet 2 — Seasonal & Weather Drivers

**Audience:** Environmental scientists, DONRE technical staff, journalists.
**Question:** "Why does pollution spike Nov–Mar, and what weather conditions drive episodes?"

**Panel A — Seasonal rhythm:**
- Monthly PM2.5 bar chart (both cities, all years averaged): `avg_value` by `month_of_year`
  with WHO 15 µg/m³ (dashed red) and QCVN 50 µg/m³ (dashed orange) reference lines.
  NE monsoon spike is unmistakable. Source: `monthly_profile`
- Diurnal hour-of-day line (0–23 UTC+7), faceted by season: Hanoi dual-peak pattern
  (06:00–08:00 inversion + rush hour; 21:00–23:00 nocturnal cooling) vs HCMC single peak.
  Source: `diurnal_profile`, split by `season` filter control

**Panel B — Weather drivers** (requires `aq_weather_daily`, new in revised plan):
- Inversion risk grouped bar: `avg_pm25` for `inversion_risk=1` vs `inversion_risk=0` days,
  by city. Quantifies the BLH/calm-wind trapping effect.
- Wet scavenging bar: same for `wet_scavenging=1` vs `=0`. Shows rain's cleansing power.
- Wind speed vs PM2.5 scatter: negative correlation illustrating dispersion physics.
- Note: all three panels use `mart_aq_weather_daily` (SPICE dataset 6).

**Panel C — Source attribution:**
- PM2.5/PM10 ratio bar by city × season (`source_indicator` colouring):
  combustion-dominated (NE monsoon Hanoi) vs mixed/crustal. Source: `pollutant_ratio`

**Tết annotation:** Reference band marking Lunar New Year windows (late Jan / early Feb)
on the monthly chart. Explains the Jan/Feb fireworks spike that is otherwise weather-anomalous.
Implemented as a QuickSight reference band (static annotation, no new mart needed).

**Filters:** city, season, year

---

### Sheet 3 — Compliance & Target Trajectory

**Audience:** Policy planners, DONRE compliance staff, World Bank/UNDP funders.
**Question:** "Are exceedances falling year-on-year? Are we on track for 2030?"

**WHO exceedance trend** (primary KPI line chart, monthly 2023→2026):
`who_exceedance_rate` per city. Add projected linear trendline to 2030 and a
"target ≤ 20%" reference line. Source: `exceedance_stats`

**QCVN exceedance trend** (secondary line):
`qcvn_exceedance_rate` — tracks against Vietnam national standard (50 µg/m³).
Source: `exceedance_stats`

**Year-over-year monthly heatmap** (city × year × month):
`avg_pm25` coloured as deviation from 2023 baseline. Immediately shows whether
a given month improved or worsened vs the same month in prior years.
Source: `annual_monthly_trend`

**p95 episode severity bar** (month × year):
`p95_pm25` — captures whether the worst days are improving even if the mean is stable.
The December 2025 peak (197 µg/m³) would stand out sharply against historical p95.
Source: `annual_monthly_trend`

**Removed from original plan:** corrected vs raw PM2.5 scatter. This is sensor QA for
data engineers — it does not belong on a policy compliance sheet.

**Filters:** city, year, parameter (pm25 default)

---

### Sheet 4 — Forecast Monitor

**Audience:** On-call data engineer, public health warning staff, operations.
**Question:** "What is forecast for the next 7 days, and is the model reliable?"

**7-day SARIMA forecast** (line chart per station):
`forecast_pm25` with `ci_lower_95` / `ci_upper_95` shaded band.
WHO (15 µg/m³) and QCVN (50 µg/m³) horizontal reference lines added so
forecasters see whether the coming week is expected to breach standards.
Source: `forecast_accuracy` (uses `forecast_pm25`, `ci_lower_95`, `ci_upper_95`)

**Forecast vs actual scatter** (per city):
`actual_pm25` (x) vs `forecast_pm25` (y) with 45° reference line.
Systematic over/under-forecast (bias) is visible as diagonal deviation.
Rolling bias badge from `rolling_bias_30d`. Source: `forecast_accuracy`

**Rolling RMSE 30d trend** (time series, per model):
CloudWatch alarm threshold at 25 µg/m³ shown as reference line.
Source: `forecast_accuracy`

**Model comparison KPI tiles** (new in revised plan):
SARIMA vs Prophet `rolling_rmse_30d` side-by-side per city.
Uses the `model` dimension already in `forecast_accuracy`.

**Filters:** location_name (default: Hanoi-US Embassy, HCMC-US Embassy), run_date (latest)

---

## Phase 4 — Published Dashboard (PENDING)

File: `terraform/quicksight_dashboard.tf` (resource commented out)

Uncomment after Phase 3 is applied. The template (`aws_quicksight_template.openaq`)
snapshots the analysis; the dashboard (`aws_quicksight_dashboard.openaq`) publishes
from that template. Re-run `terraform apply` after analysis updates to publish v2, v3, etc.

---

## Phase 5 — Deployment Steps

```bash
# Phase 1+2 (already done — run these to apply if not yet applied):
cd terraform/
terraform init -upgrade
terraform apply \
  -target=aws_iam_role.quicksight_service \
  -target=aws_iam_role_policy.quicksight_service \
  -target=aws_quicksight_data_source.athena \
  -target=aws_quicksight_data_set.daily_aqi \
  -target=aws_quicksight_data_set.health_summary \
  -target=aws_quicksight_data_set.annual_monthly_trend \
  -target=aws_quicksight_data_set.monthly_profile \
  -target=aws_quicksight_data_set.diurnal_profile \
  -target=aws_quicksight_data_set.aq_weather_daily \
  -target=aws_quicksight_data_set.exceedance_stats \
  -target=aws_quicksight_data_set.pollutant_ratio \
  -target=aws_quicksight_data_set.forecast_accuracy

# Monitor SPICE ingestion (run per dataset):
aws quicksight list-ingestions \
  --aws-account-id $(aws sts get-caller-identity --query Account --output text) \
  --data-set-id openaq-daily-aqi \
  --region ap-southeast-1 \
  --query 'Ingestions[0].{Status:IngestionStatus,Rows:RowInfo.RowsIngested,Started:CreatedTime}'

# Trigger manual refresh if needed:
aws quicksight create-ingestion \
  --aws-account-id $(aws sts get-caller-identity --query Account --output text) \
  --data-set-id openaq-aq-weather-daily \
  --ingestion-id manual-$(date +%Y%m%d-%H%M%S) \
  --region ap-southeast-1

# Phase 3 — build analysis in console, then export:
aws quicksight describe-analysis-definition \
  --aws-account-id $(aws sts get-caller-identity --query Account --output text) \
  --analysis-id openaq-air-quality-analysis \
  --query 'Definition' \
  > terraform/quicksight_analysis_definition.json

# Phase 4 — after Phase 3 terraform apply:
terraform apply \
  -target=aws_quicksight_template.openaq \
  -target=aws_quicksight_dashboard.openaq
```

---

## Cost Estimate

| Item | Detail | Monthly |
|------|--------|---------|
| QuickSight Author license | 1 Author | ~$18.00 |
| SPICE storage | 9 datasets × ~10–50 MB each ≈ ~200 MB total | ~$0.02 (first 10 GB free) |
| Athena scans | $0 after SPICE (no live queries on dashboard load) | $0.00 |
| **Total addition** | | **~$18.02/month** |

Pipeline total with QuickSight: ~$19.63/month. Without QuickSight: $1.61/month.

To reduce: use QuickSight 30-day free trial (1 Author included).

---

## File Structure

```
terraform/
  quicksight_iam.tf                    ← Phase 1: service role + user ARN local  [DONE]
  quicksight_datasource.tf             ← Phase 2: Athena data source              [DONE]
  quicksight_datasets.tf               ← Phase 2: 9 SPICE datasets + schedules    [DONE]
  quicksight_analysis.tf               ← Phase 3: analysis resource (commented)   [PENDING]
  quicksight_dashboard.tf              ← Phase 4: template + dashboard (commented) [PENDING]
  quicksight_analysis_definition.json  ← Phase 3: exported from console            [NOT YET]
```

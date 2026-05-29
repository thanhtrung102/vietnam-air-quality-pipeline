# ── QuickSight Analysis (Phase 3) ────────────────────────────────────────────
#
# STATUS: DONE — created programmatically via terraform/create_analysis.py.
#
# The analysis was built with Python/boto3 (not the console) because the full
# visual definition JSON is authoritative and too complex to express in HCL.
# The definition is stored in quicksight_analysis_definition.json and can be
# re-applied by re-running create_analysis.py.
#
# Terraform manages:
#   - Analysis ID, name, permissions, tags
#   - Dataset identifier → ARN wiring
#
# Terraform does NOT manage (ignore_changes):
#   - The full visual definition (sheets, visuals, field wells, filters)
#     → edit and re-run create_analysis.py to update visuals
#
# To import after first apply:
#   terraform import aws_quicksight_analysis.openaq \
#     703668403514/openaq-air-quality-analysis
#
# ── Dataset identifier → SPICE dataset mapping ───────────────────────────────
#
# Identifier              | Terraform resource
# ─────────────────────── | ──────────────────────────────────────────────────
# "daily-aqi"             | aws_quicksight_data_set.daily_aqi
# "health-summary"        | aws_quicksight_data_set.health_summary
# "annual-monthly-trend"  | aws_quicksight_data_set.annual_monthly_trend
# "monthly-profile"       | aws_quicksight_data_set.monthly_profile
# "diurnal-profile"       | aws_quicksight_data_set.diurnal_profile
# "aq-weather-daily"      | aws_quicksight_data_set.aq_weather_daily
# "exceedance-stats"      | aws_quicksight_data_set.exceedance_stats
# "pollutant-ratio"       | aws_quicksight_data_set.pollutant_ratio
# "forecast-accuracy"     | aws_quicksight_data_set.forecast_accuracy
#
# ── Sheet summary ─────────────────────────────────────────────────────────────
#
# Sheet 1 — Executive Health Scorecard
#   Datasets: health-summary, annual-monthly-trend
#   Visuals:  5 KPIs (cigarette equiv, WHO compliance %, avg PM2.5, unhealthy days,
#             hazardous days), stacked bar (health day breakdown by city),
#             line (annual PM2.5 trend), line (WHO exceedance rate trend)
#
# Sheet 2 — Seasonal & Weather Drivers
#   Datasets: monthly-profile, diurnal-profile, aq-weather-daily, pollutant-ratio
#   Visuals:  monthly PM2.5 bar (WHO/QCVN ref lines), diurnal 0-23h line,
#             inversion risk grouped bar, wet scavenging grouped bar,
#             wind speed vs PM2.5 bar, PM2.5/PM10 ratio bar
#
# Sheet 3 — Compliance & Target Trajectory
#   Datasets: exceedance-stats, annual-monthly-trend
#   Visuals:  WHO exceedance rate trend (target ≤20% ref line), QCVN exceedance
#             trend, YoY monthly PM2.5 heatmap, p95 episode severity bar
#
# Sheet 4 — Forecast Monitor
#   Datasets: forecast-accuracy
#   Visuals:  4 KPIs (SARIMA RMSE, Prophet RMSE, rolling RMSE 30d, rolling bias),
#             7-day forecast line (WHO/QCVN ref lines), CI bounds line,
#             actual vs forecast grouped bar, rolling RMSE 30d trend,
#             holdout RMSE by model bar

resource "aws_quicksight_analysis" "openaq" {
  aws_account_id = data.aws_caller_identity.current.account_id
  analysis_id    = "openaq-air-quality-analysis"
  name           = "Vietnam Air Quality Analysis"

  definition {
    data_set_identifiers_declarations {
      identifier   = "daily-aqi"
      data_set_arn = aws_quicksight_data_set.daily_aqi.arn
    }
    data_set_identifiers_declarations {
      identifier   = "health-summary"
      data_set_arn = aws_quicksight_data_set.health_summary.arn
    }
    data_set_identifiers_declarations {
      identifier   = "annual-monthly-trend"
      data_set_arn = aws_quicksight_data_set.annual_monthly_trend.arn
    }
    data_set_identifiers_declarations {
      identifier   = "monthly-profile"
      data_set_arn = aws_quicksight_data_set.monthly_profile.arn
    }
    data_set_identifiers_declarations {
      identifier   = "diurnal-profile"
      data_set_arn = aws_quicksight_data_set.diurnal_profile.arn
    }
    data_set_identifiers_declarations {
      identifier   = "aq-weather-daily"
      data_set_arn = aws_quicksight_data_set.aq_weather_daily.arn
    }
    data_set_identifiers_declarations {
      identifier   = "exceedance-stats"
      data_set_arn = aws_quicksight_data_set.exceedance_stats.arn
    }
    data_set_identifiers_declarations {
      identifier   = "pollutant-ratio"
      data_set_arn = aws_quicksight_data_set.pollutant_ratio.arn
    }
    data_set_identifiers_declarations {
      identifier   = "forecast-accuracy"
      data_set_arn = aws_quicksight_data_set.forecast_accuracy.arn
    }
  }

  permissions {
    actions = [
      "quicksight:DescribeAnalysis",
      "quicksight:DescribeAnalysisPermissions",
      "quicksight:UpdateAnalysis",
      "quicksight:UpdateAnalysisPermissions",
      "quicksight:DeleteAnalysis",
      "quicksight:QueryAnalysis",
      "quicksight:RestoreAnalysis",
    ]
    principal = local.quicksight_user_arn
  }

  # The full visual definition (sheets, visuals, field wells, filters, layouts)
  # is managed by create_analysis.py, not Terraform. Ignoring definition drift
  # prevents Terraform from overwriting visuals edited in the console or via script.
  lifecycle {
    ignore_changes = [definition]
  }

  tags = local.common_tags
}

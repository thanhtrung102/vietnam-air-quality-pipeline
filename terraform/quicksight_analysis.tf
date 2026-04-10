# ── QuickSight Analysis (Phase 3) ────────────────────────────────────────────
#
# STATUS: Pending console creation. Do NOT apply until Step 2 below is complete.
#
# Phase 3 requires a console-first workflow because QuickSight's visual
# definition schema (drag-and-drop field assignments, axis configs, color rules)
# is impractical to author in HCL from scratch. The correct flow is:
#
#   Step 1 — Apply Phase 2 (already done):
#     terraform apply -target=aws_quicksight_data_set.daily_aqi \
#                     -target=aws_quicksight_data_set.health_summary \
#                     ... (all 9 datasets)
#
#   Step 2 — Build the 4-sheet analysis in the QuickSight console:
#     AWS Console → QuickSight → Analyses → New analysis
#     Use the 9 deployed SPICE datasets as sources.
#     Analysis ID to use: openaq-air-quality-analysis
#     See docs/quicksight_plan.md §Phase 3 for the full visual specification
#     (sheet layouts, visual types, field assignments, reference lines).
#
#   Step 3 — Export the definition:
#     aws quicksight describe-analysis-definition \
#       --aws-account-id $(aws sts get-caller-identity --query Account --output text) \
#       --analysis-id openaq-air-quality-analysis \
#       --query 'Definition' \
#       > terraform/quicksight_analysis_definition.json
#
#   Step 4 — Uncomment the resource block below, paste the definition, then:
#     terraform import aws_quicksight_analysis.openaq \
#       <account_id>/openaq-air-quality-analysis
#     terraform apply
#
# ── Dataset placeholder → SPICE dataset mapping ──────────────────────────────
#
# Placeholder name (used in definition JSON)  | Terraform resource
# ──────────────────────────────────────────  | ──────────────────────────────
# "daily-aqi"                                 | aws_quicksight_data_set.daily_aqi
# "health-summary"                            | aws_quicksight_data_set.health_summary
# "annual-monthly-trend"                      | aws_quicksight_data_set.annual_monthly_trend
# "monthly-profile"                           | aws_quicksight_data_set.monthly_profile
# "diurnal-profile"                           | aws_quicksight_data_set.diurnal_profile
# "aq-weather-daily"                          | aws_quicksight_data_set.aq_weather_daily
# "exceedance-stats"                          | aws_quicksight_data_set.exceedance_stats
# "pollutant-ratio"                           | aws_quicksight_data_set.pollutant_ratio
# "forecast-accuracy"                         | aws_quicksight_data_set.forecast_accuracy
#
# ── Sheet layout (see docs/quicksight_plan.md for full visual specs) ─────────
#
# Sheet 1 — Executive Health Scorecard
#   Datasets: daily-aqi, health-summary, annual-monthly-trend
#   Visuals:  cigarette-equivalent KPI, 2030 policy target gauges,
#             AQI calendar heatmap (3-year), annual health day stacked bar
#
# Sheet 2 — Seasonal & Weather Drivers
#   Datasets: monthly-profile, diurnal-profile, aq-weather-daily, pollutant-ratio
#   Visuals:  monthly PM2.5 bar with WHO/QCVN lines, diurnal 0-23 UTC+7 line,
#             inversion_risk grouped bar, wet_scavenging bar, PM2.5/PM10 ratio
#
# Sheet 3 — Compliance & Target Trajectory
#   Datasets: exceedance-stats, annual-monthly-trend
#   Visuals:  WHO exceedance rate trend (2023→2026), QCVN exceedance trend,
#             YoY monthly heatmap, p95 episode severity bar
#
# Sheet 4 — Forecast Monitor
#   Datasets: forecast-accuracy, daily-aqi
#   Visuals:  7-day SARIMA forecast with CI bands and WHO/QCVN reference lines,
#             forecast vs actual scatter, rolling RMSE 30d, SARIMA vs Prophet KPI

# ── UNCOMMENT after Step 3 export and paste Definition content ────────────────

# resource "aws_quicksight_analysis" "openaq" {
#   aws_account_id = data.aws_caller_identity.current.account_id
#   analysis_id    = "openaq-air-quality-analysis"
#   name           = "Vietnam Air Quality Analysis"
#
#   definition {
#     data_set_identifiers_declaration {
#       identifier   = "daily-aqi"
#       data_set_arn = aws_quicksight_data_set.daily_aqi.arn
#     }
#     data_set_identifiers_declaration {
#       identifier   = "health-summary"
#       data_set_arn = aws_quicksight_data_set.health_summary.arn
#     }
#     data_set_identifiers_declaration {
#       identifier   = "annual-monthly-trend"
#       data_set_arn = aws_quicksight_data_set.annual_monthly_trend.arn
#     }
#     data_set_identifiers_declaration {
#       identifier   = "monthly-profile"
#       data_set_arn = aws_quicksight_data_set.monthly_profile.arn
#     }
#     data_set_identifiers_declaration {
#       identifier   = "diurnal-profile"
#       data_set_arn = aws_quicksight_data_set.diurnal_profile.arn
#     }
#     data_set_identifiers_declaration {
#       identifier   = "aq-weather-daily"
#       data_set_arn = aws_quicksight_data_set.aq_weather_daily.arn
#     }
#     data_set_identifiers_declaration {
#       identifier   = "exceedance-stats"
#       data_set_arn = aws_quicksight_data_set.exceedance_stats.arn
#     }
#     data_set_identifiers_declaration {
#       identifier   = "pollutant-ratio"
#       data_set_arn = aws_quicksight_data_set.pollutant_ratio.arn
#     }
#     data_set_identifiers_declaration {
#       identifier   = "forecast-accuracy"
#       data_set_arn = aws_quicksight_data_set.forecast_accuracy.arn
#     }
#
#     # Paste exported sheet/visual definitions here from:
#     # terraform/quicksight_analysis_definition.json
#   }
#
#   permissions {
#     actions = [
#       "quicksight:DescribeAnalysis",
#       "quicksight:DescribeAnalysisPermissions",
#       "quicksight:UpdateAnalysis",
#       "quicksight:UpdateAnalysisPermissions",
#       "quicksight:DeleteAnalysis",
#       "quicksight:QueryAnalysis",
#       "quicksight:RestoreAnalysis",
#     ]
#     principal = local.quicksight_user_arn
#   }
#
#   tags = local.common_tags
# }

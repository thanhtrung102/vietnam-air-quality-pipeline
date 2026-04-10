# ── QuickSight Dashboard (Phase 4) ───────────────────────────────────────────
#
# STATUS: Pending Phase 3 completion. Do NOT apply until aws_quicksight_analysis.openaq
#         is created and Terraform-managed (Phase 3 Step 4 complete).
#
# Once the analysis resource is uncommented and applied in quicksight_analysis.tf,
# uncomment both blocks below and run:
#   terraform apply -target=aws_quicksight_template.openaq
#   terraform apply -target=aws_quicksight_dashboard.openaq
#
# The template snapshots the current analysis version. Re-run terraform apply
# after any analysis updates to publish a new dashboard version.

# ── UNCOMMENT after Phase 3 is applied ───────────────────────────────────────

# resource "aws_quicksight_template" "openaq" {
#   aws_account_id  = data.aws_caller_identity.current.account_id
#   template_id     = "openaq-air-quality-template"
#   name            = "Vietnam Air Quality Template"
#   version_description = "v1"
#
#   source_entity {
#     source_analysis {
#       arn = aws_quicksight_analysis.openaq.arn
#
#       data_set_references {
#         data_set_arn         = aws_quicksight_data_set.daily_aqi.arn
#         data_set_placeholder = "daily-aqi"
#       }
#       data_set_references {
#         data_set_arn         = aws_quicksight_data_set.health_summary.arn
#         data_set_placeholder = "health-summary"
#       }
#       data_set_references {
#         data_set_arn         = aws_quicksight_data_set.annual_monthly_trend.arn
#         data_set_placeholder = "annual-monthly-trend"
#       }
#       data_set_references {
#         data_set_arn         = aws_quicksight_data_set.monthly_profile.arn
#         data_set_placeholder = "monthly-profile"
#       }
#       data_set_references {
#         data_set_arn         = aws_quicksight_data_set.diurnal_profile.arn
#         data_set_placeholder = "diurnal-profile"
#       }
#       data_set_references {
#         data_set_arn         = aws_quicksight_data_set.aq_weather_daily.arn
#         data_set_placeholder = "aq-weather-daily"
#       }
#       data_set_references {
#         data_set_arn         = aws_quicksight_data_set.exceedance_stats.arn
#         data_set_placeholder = "exceedance-stats"
#       }
#       data_set_references {
#         data_set_arn         = aws_quicksight_data_set.pollutant_ratio.arn
#         data_set_placeholder = "pollutant-ratio"
#       }
#       data_set_references {
#         data_set_arn         = aws_quicksight_data_set.forecast_accuracy.arn
#         data_set_placeholder = "forecast-accuracy"
#       }
#     }
#   }
#
#   permissions {
#     actions = [
#       "quicksight:DescribeTemplate",
#       "quicksight:DescribeTemplatePermissions",
#       "quicksight:UpdateTemplate",
#       "quicksight:UpdateTemplatePermissions",
#       "quicksight:DeleteTemplate",
#       "quicksight:CreateTemplateAlias",
#       "quicksight:DescribeTemplateAlias",
#       "quicksight:UpdateTemplateAlias",
#       "quicksight:DeleteTemplateAlias",
#       "quicksight:ListTemplateAliases",
#       "quicksight:ListTemplateVersions",
#     ]
#     principal = local.quicksight_user_arn
#   }
#
#   tags = local.common_tags
# }

# resource "aws_quicksight_dashboard" "openaq" {
#   aws_account_id      = data.aws_caller_identity.current.account_id
#   dashboard_id        = "openaq-air-quality"
#   name                = "Vietnam Air Quality Analytics"
#   version_description = "v1"
#
#   source_entity {
#     source_template {
#       arn = aws_quicksight_template.openaq.arn
#
#       data_set_references {
#         data_set_arn         = aws_quicksight_data_set.daily_aqi.arn
#         data_set_placeholder = "daily-aqi"
#       }
#       data_set_references {
#         data_set_arn         = aws_quicksight_data_set.health_summary.arn
#         data_set_placeholder = "health-summary"
#       }
#       data_set_references {
#         data_set_arn         = aws_quicksight_data_set.annual_monthly_trend.arn
#         data_set_placeholder = "annual-monthly-trend"
#       }
#       data_set_references {
#         data_set_arn         = aws_quicksight_data_set.monthly_profile.arn
#         data_set_placeholder = "monthly-profile"
#       }
#       data_set_references {
#         data_set_arn         = aws_quicksight_data_set.diurnal_profile.arn
#         data_set_placeholder = "diurnal-profile"
#       }
#       data_set_references {
#         data_set_arn         = aws_quicksight_data_set.aq_weather_daily.arn
#         data_set_placeholder = "aq-weather-daily"
#       }
#       data_set_references {
#         data_set_arn         = aws_quicksight_data_set.exceedance_stats.arn
#         data_set_placeholder = "exceedance-stats"
#       }
#       data_set_references {
#         data_set_arn         = aws_quicksight_data_set.pollutant_ratio.arn
#         data_set_placeholder = "pollutant-ratio"
#       }
#       data_set_references {
#         data_set_arn         = aws_quicksight_data_set.forecast_accuracy.arn
#         data_set_placeholder = "forecast-accuracy"
#       }
#     }
#   }
#
#   dashboard_publish_options {
#     ad_hoc_filtering_option  { availability_status = "ENABLED" }
#     export_to_csv_option     { availability_status = "ENABLED" }
#     sheet_controls_option    { visibility_status   = "EXPANDED" }
#   }
#
#   permissions {
#     actions = [
#       "quicksight:DescribeDashboard",
#       "quicksight:ListDashboardVersions",
#       "quicksight:UpdateDashboardPermissions",
#       "quicksight:QueryDashboard",
#       "quicksight:UpdateDashboard",
#       "quicksight:DeleteDashboard",
#       "quicksight:DescribeDashboardPermissions",
#       "quicksight:UpdateDashboardPublishedVersion",
#     ]
#     principal = local.quicksight_user_arn
#   }
#
#   tags = local.common_tags
# }

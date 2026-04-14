# ── QuickSight Datasets (Phase 2.2 & 2.3) — DIRECT_QUERY mode ──────────────────
#
# Nine datasets, one per mart table, all using DIRECT_QUERY (live Athena queries).
# Real-time: each dashboard load queries Athena directly — no refresh lag.
# Each dataset refreshes daily at 04:00 UTC — after dbt completes (~02:45 UTC).
#
# Dataset → Sheet mapping (revised 4-sheet design):
#   ds_daily_aqi            → Sheet 1 (Executive Health Scorecard)
#   ds_health_summary       → Sheet 1
#   ds_annual_monthly_trend → Sheet 1 & 3
#   ds_monthly_profile      → Sheet 2 (Seasonal & Weather Drivers)
#   ds_diurnal_profile      → Sheet 2
#   ds_aq_weather_daily     → Sheet 2 (inversion_risk, wet_scavenging)
#   ds_exceedance_stats     → Sheet 3 (Compliance & Target Trajectory)
#   ds_pollutant_ratio      → Sheet 3
#   ds_forecast_accuracy    → Sheet 4 (Forecast Monitor)
#
# Glue schema: openaq_mart  (dbt creates and manages this database)
# Catalog:     AwsDataCatalog  (default AWS Glue integration name for Athena)

# ── Shared locals ─────────────────────────────────────────────────────────────

locals {
  qs_dataset_actions = [
    "quicksight:DescribeDataSet",
    "quicksight:DescribeDataSetPermissions",
    "quicksight:PassDataSet",
    "quicksight:DescribeIngestion",
    "quicksight:ListIngestions",
    "quicksight:UpdateDataSet",
    "quicksight:DeleteDataSet",
    "quicksight:CreateIngestion",
    "quicksight:CancelIngestion",
    "quicksight:UpdateDataSetPermissions",
  ]

  qs_catalog = "AwsDataCatalog"
  qs_schema  = "openaq_mart"
}

# ─────────────────────────────────────────────────────────────────────────────
# Dataset 1: ds_daily_aqi
# Grain: measurement_date × location_id
# Sheet: 1 — composite AQI time series, Leaflet map feed, calendar heat map
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_quicksight_data_set" "daily_aqi" {
  aws_account_id = data.aws_caller_identity.current.account_id
  data_set_id    = "openaq-daily-aqi"
  name           = "OpenAQ – Daily Composite AQI"
  import_mode    = "DIRECT_QUERY"

  physical_table_map {
    physical_table_map_id = "mart-daily-aqi"
    relational_table {
      data_source_arn = aws_quicksight_data_source.athena.arn
      catalog         = local.qs_catalog
      schema          = local.qs_schema
      name            = "mart_daily_aqi"
      input_columns {
        name = "measurement_date"
        type = "DATETIME"
      }
      input_columns {
        name = "location_id"
        type = "INTEGER"
      }
      input_columns {
        name = "location_name"
        type = "STRING"
      }
      input_columns {
        name = "city"
        type = "STRING"
      }
      input_columns {
        name = "province"
        type = "STRING"
      }
      input_columns {
        name = "station_lat"
        type = "DECIMAL"
      }
      input_columns {
        name = "station_lon"
        type = "DECIMAL"
      }
      input_columns {
        name = "sensor_type"
        type = "STRING"
      }
      input_columns {
        name = "composite_aqi"
        type = "INTEGER"
      }
      input_columns {
        name = "dominant_pollutant"
        type = "STRING"
      }
      input_columns {
        name = "health_category"
        type = "STRING"
      }
      input_columns {
        name = "pm25_avg"
        type = "DECIMAL"
      }
      input_columns {
        name = "cigarette_equivalent"
        type = "DECIMAL"
      }
    }
  }

  permissions {
    actions   = local.qs_dataset_actions
    principal = local.quicksight_user_arn
  }

  tags = local.common_tags
}


# ─────────────────────────────────────────────────────────────────────────────
# Dataset 2: ds_health_summary
# Grain: city × year
# Sheet: 1 — annual health-day stacked bar, risk KPI tiles
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_quicksight_data_set" "health_summary" {
  aws_account_id = data.aws_caller_identity.current.account_id
  data_set_id    = "openaq-health-summary"
  name           = "OpenAQ – Annual Health Summary by City"
  import_mode    = "DIRECT_QUERY"

  physical_table_map {
    physical_table_map_id = "mart-health-summary"
    relational_table {
      data_source_arn = aws_quicksight_data_source.athena.arn
      catalog         = local.qs_catalog
      schema          = local.qs_schema
      name            = "mart_health_summary"
      input_columns {
        name = "city"
        type = "STRING"
      }
      input_columns {
        name = "province"
        type = "STRING"
      }
      input_columns {
        name = "year"
        type = "INTEGER"
      }
      input_columns {
        name = "total_days"
        type = "INTEGER"
      }
      input_columns {
        name = "good_days"
        type = "INTEGER"
      }
      input_columns {
        name = "moderate_days"
        type = "INTEGER"
      }
      input_columns {
        name = "usg_days"
        type = "INTEGER"
      }
      input_columns {
        name = "unhealthy_days"
        type = "INTEGER"
      }
      input_columns {
        name = "very_unhealthy_days"
        type = "INTEGER"
      }
      input_columns {
        name = "hazardous_days"
        type = "INTEGER"
      }
      input_columns {
        name = "who_compliant_days"
        type = "INTEGER"
      }
      input_columns {
        name = "who_compliance_pct"
        type = "DECIMAL"
      }
      input_columns {
        name = "avg_pm25"
        type = "DECIMAL"
      }
      input_columns {
        name = "avg_cigarette_equivalent"
        type = "DECIMAL"
      }
      input_columns {
        name = "max_pm25"
        type = "DECIMAL"
      }
      input_columns {
        name = "risk_label"
        type = "STRING"
      }
    }
  }

  permissions {
    actions   = local.qs_dataset_actions
    principal = local.quicksight_user_arn
  }

  tags = local.common_tags
}


# ─────────────────────────────────────────────────────────────────────────────
# Dataset 3: ds_annual_monthly_trend
# Grain: city × year × month_of_year
# Sheets: 1 (calendar heat map) and 3 (YoY monthly line chart)
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_quicksight_data_set" "annual_monthly_trend" {
  aws_account_id = data.aws_caller_identity.current.account_id
  data_set_id    = "openaq-annual-monthly-trend"
  name           = "OpenAQ – Annual Monthly PM2.5 Trend"
  import_mode    = "DIRECT_QUERY"

  physical_table_map {
    physical_table_map_id = "mart-annual-monthly-trend"
    relational_table {
      data_source_arn = aws_quicksight_data_source.athena.arn
      catalog         = local.qs_catalog
      schema          = local.qs_schema
      name            = "mart_annual_monthly_trend"
      input_columns {
        name = "city"
        type = "STRING"
      }
      input_columns {
        name = "province"
        type = "STRING"
      }
      input_columns {
        name = "year"
        type = "INTEGER"
      }
      input_columns {
        name = "month_of_year"
        type = "INTEGER"
      }
      input_columns {
        name = "total_days"
        type = "INTEGER"
      }
      input_columns {
        name = "avg_pm25"
        type = "DECIMAL"
      }
      input_columns {
        name = "max_pm25"
        type = "DECIMAL"
      }
      input_columns {
        name = "p95_pm25"
        type = "DECIMAL"
      }
      input_columns {
        name = "who_exceedance_rate"
        type = "DECIMAL"
      }
      input_columns {
        name = "qcvn_exceedance_rate"
        type = "DECIMAL"
      }
    }
  }

  permissions {
    actions   = local.qs_dataset_actions
    principal = local.quicksight_user_arn
  }

  tags = local.common_tags
}


# ─────────────────────────────────────────────────────────────────────────────
# Dataset 4: ds_monthly_profile
# Grain: location_id × parameter × month_of_year  (multi-year climatology)
# Sheet: 2 — "typical year" seasonal bar chart per station
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_quicksight_data_set" "monthly_profile" {
  aws_account_id = data.aws_caller_identity.current.account_id
  data_set_id    = "openaq-monthly-profile"
  name           = "OpenAQ – Monthly Climatological Profile"
  import_mode    = "DIRECT_QUERY"

  physical_table_map {
    physical_table_map_id = "mart-monthly-profile"
    relational_table {
      data_source_arn = aws_quicksight_data_source.athena.arn
      catalog         = local.qs_catalog
      schema          = local.qs_schema
      name            = "mart_monthly_profile"
      input_columns {
        name = "location_id"
        type = "INTEGER"
      }
      input_columns {
        name = "location_name"
        type = "STRING"
      }
      input_columns {
        name = "city"
        type = "STRING"
      }
      input_columns {
        name = "province"
        type = "STRING"
      }
      input_columns {
        name = "sensor_type"
        type = "STRING"
      }
      input_columns {
        name = "parameter"
        type = "STRING"
      }
      input_columns {
        name = "month_of_year"
        type = "INTEGER"
      }
      input_columns {
        name = "season"
        type = "STRING"
      }
      input_columns {
        name = "avg_value"
        type = "DECIMAL"
      }
      input_columns {
        name = "max_value"
        type = "DECIMAL"
      }
      input_columns {
        name = "min_value"
        type = "DECIMAL"
      }
      input_columns {
        name = "p95_value"
        type = "DECIMAL"
      }
      input_columns {
        name = "reading_count"
        type = "INTEGER"
      }
      input_columns {
        name = "day_count"
        type = "INTEGER"
      }
    }
  }

  permissions {
    actions   = local.qs_dataset_actions
    principal = local.quicksight_user_arn
  }

  tags = local.common_tags
}


# ─────────────────────────────────────────────────────────────────────────────
# Dataset 5: ds_diurnal_profile
# Grain: location_id × parameter × hour_of_day × day_type × season
# Sheet: 2 — hour-of-day line chart (0–23 UTC+7), weekday vs weekend comparison
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_quicksight_data_set" "diurnal_profile" {
  aws_account_id = data.aws_caller_identity.current.account_id
  data_set_id    = "openaq-diurnal-profile"
  name           = "OpenAQ – Diurnal (Hour-of-Day) Profile"
  import_mode    = "DIRECT_QUERY"

  physical_table_map {
    physical_table_map_id = "mart-diurnal-profile"
    relational_table {
      data_source_arn = aws_quicksight_data_source.athena.arn
      catalog         = local.qs_catalog
      schema          = local.qs_schema
      name            = "mart_diurnal_profile"
      input_columns {
        name = "location_id"
        type = "INTEGER"
      }
      input_columns {
        name = "location_name"
        type = "STRING"
      }
      input_columns {
        name = "city"
        type = "STRING"
      }
      input_columns {
        name = "province"
        type = "STRING"
      }
      input_columns {
        name = "sensor_type"
        type = "STRING"
      }
      input_columns {
        name = "parameter"
        type = "STRING"
      }
      input_columns {
        name = "hour_of_day"
        type = "INTEGER"
      }
      input_columns {
        name = "day_type"
        type = "STRING"
      }
      input_columns {
        name = "season"
        type = "STRING"
      }
      input_columns {
        name = "avg_value"
        type = "DECIMAL"
      }
      input_columns {
        name = "max_value"
        type = "DECIMAL"
      }
      input_columns {
        name = "min_value"
        type = "DECIMAL"
      }
      input_columns {
        name = "reading_count"
        type = "INTEGER"
      }
    }
  }

  permissions {
    actions   = local.qs_dataset_actions
    principal = local.quicksight_user_arn
  }

  tags = local.common_tags
}


# ─────────────────────────────────────────────────────────────────────────────
# Dataset 6: ds_exceedance_stats
# Grain: city × parameter × year × month_of_year
# Sheet: 3 — WHO/QCVN exceedance trend, monthly compliance reporting
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_quicksight_data_set" "exceedance_stats" {
  aws_account_id = data.aws_caller_identity.current.account_id
  data_set_id    = "openaq-exceedance-stats"
  name           = "OpenAQ – Monthly Exceedance Statistics"
  import_mode    = "DIRECT_QUERY"

  physical_table_map {
    physical_table_map_id = "mart-exceedance-stats"
    relational_table {
      data_source_arn = aws_quicksight_data_source.athena.arn
      catalog         = local.qs_catalog
      schema          = local.qs_schema
      name            = "mart_exceedance_stats"
      input_columns {
        name = "city"
        type = "STRING"
      }
      input_columns {
        name = "parameter"
        type = "STRING"
      }
      input_columns {
        name = "year"
        type = "INTEGER"
      }
      input_columns {
        name = "month_of_year"
        type = "INTEGER"
      }
      input_columns {
        name = "total_days"
        type = "INTEGER"
      }
      input_columns {
        name = "who_exceedance_days"
        type = "INTEGER"
      }
      input_columns {
        name = "qcvn_exceedance_days"
        type = "INTEGER"
      }
      input_columns {
        name = "who_exceedance_rate"
        type = "DECIMAL"
      }
      input_columns {
        name = "qcvn_exceedance_rate"
        type = "DECIMAL"
      }
      input_columns {
        name = "avg_pm25"
        type = "DECIMAL"
      }
      input_columns {
        name = "p95_pm25"
        type = "DECIMAL"
      }
    }
  }

  permissions {
    actions   = local.qs_dataset_actions
    principal = local.quicksight_user_arn
  }

  tags = local.common_tags
}


# ─────────────────────────────────────────────────────────────────────────────
# Dataset 7: ds_pollutant_ratio
# Grain: location_id × measurement_date
# Sheet: 3 — PM2.5/PM10 ratio bar by season, combustion vs dust indicator
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_quicksight_data_set" "pollutant_ratio" {
  aws_account_id = data.aws_caller_identity.current.account_id
  data_set_id    = "openaq-pollutant-ratio"
  name           = "OpenAQ – PM2.5 / PM10 Pollutant Ratio"
  import_mode    = "DIRECT_QUERY"

  physical_table_map {
    physical_table_map_id = "mart-pollutant-ratio"
    relational_table {
      data_source_arn = aws_quicksight_data_source.athena.arn
      catalog         = local.qs_catalog
      schema          = local.qs_schema
      name            = "mart_pollutant_ratio"
      input_columns {
        name = "location_id"
        type = "INTEGER"
      }
      input_columns {
        name = "location_name"
        type = "STRING"
      }
      input_columns {
        name = "city"
        type = "STRING"
      }
      input_columns {
        name = "province"
        type = "STRING"
      }
      input_columns {
        name = "measurement_date"
        type = "DATETIME"
      }
      input_columns {
        name = "pm25_avg"
        type = "DECIMAL"
      }
      input_columns {
        name = "pm10_avg"
        type = "DECIMAL"
      }
      input_columns {
        name = "pm25_pm10_ratio"
        type = "DECIMAL"
      }
      input_columns {
        name = "source_indicator"
        type = "STRING"
      }
    }
  }

  permissions {
    actions   = local.qs_dataset_actions
    principal = local.quicksight_user_arn
  }

  tags = local.common_tags
}


# ─────────────────────────────────────────────────────────────────────────────
# Dataset 8: ds_forecast_accuracy
# Grain: location_id × model × forecast_date
# Sheet: 4 — 7-day SARIMA forecast ribbon, forecast vs actual scatter,
#             rolling 30-day RMSE trend (alarm threshold: 25 µg/m³)
#
# mart_forecast_accuracy already embeds forecast values (from the Lambda-
# written mart_daily_forecast external table) and observed actuals (from
# mart_daily_air_quality). No additional physical tables needed.
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_quicksight_data_set" "forecast_accuracy" {
  aws_account_id = data.aws_caller_identity.current.account_id
  data_set_id    = "openaq-forecast-accuracy"
  name           = "OpenAQ – Forecast vs Actuals & Rolling RMSE"
  import_mode    = "DIRECT_QUERY"

  physical_table_map {
    physical_table_map_id = "mart-forecast-accuracy"
    relational_table {
      data_source_arn = aws_quicksight_data_source.athena.arn
      catalog         = local.qs_catalog
      schema          = local.qs_schema
      name            = "mart_forecast_accuracy"
      input_columns {
        name = "forecast_date"
        type = "DATETIME"
      }
      input_columns {
        name = "location_id"
        type = "INTEGER"
      }
      input_columns {
        name = "location_name"
        type = "STRING"
      }
      input_columns {
        name = "city"
        type = "STRING"
      }
      input_columns {
        name = "model"
        type = "STRING"
      }
      input_columns {
        name = "generated_at"
        type = "DATETIME"
      }
      input_columns {
        name = "forecast_pm25"
        type = "DECIMAL"
      }
      input_columns {
        name = "forecast_aqi"
        type = "INTEGER"
      }
      input_columns {
        name = "forecast_aqi_category"
        type = "STRING"
      }
      input_columns {
        name = "ci_lower_95"
        type = "DECIMAL"
      }
      input_columns {
        name = "ci_upper_95"
        type = "DECIMAL"
      }
      input_columns {
        name = "holdout_rmse"
        type = "DECIMAL"
      }
      input_columns {
        name = "actual_pm25"
        type = "DECIMAL"
      }
      input_columns {
        name = "error"
        type = "DECIMAL"
      }
      input_columns {
        name = "abs_error"
        type = "DECIMAL"
      }
      input_columns {
        name = "squared_error"
        type = "DECIMAL"
      }
      input_columns {
        name = "rolling_rmse_7d"
        type = "DECIMAL"
      }
      input_columns {
        name = "rolling_rmse_30d"
        type = "DECIMAL"
      }
      input_columns {
        name = "rolling_mae_30d"
        type = "DECIMAL"
      }
      input_columns {
        name = "rolling_bias_30d"
        type = "DECIMAL"
      }
    }
  }

  permissions {
    actions   = local.qs_dataset_actions
    principal = local.quicksight_user_arn
  }

  tags = local.common_tags
}


# ─────────────────────────────────────────────────────────────────────────────
# Dataset 9: ds_aq_weather_daily
# Grain: measurement_date × location_id (PM2.5 + ERA5 weather, left-joined)
# Sheet: 2 — weather driver panels (inversion_risk, wet_scavenging, wind vs PM2.5)
#
# This is the only dataset that crosses air quality and meteorology at daily
# station grain. It enables the "why does it spike in winter" analysis:
#   - inversion_risk (1/0): BLH < 500m AND wind < 2 m/s → trapped surface emissions
#   - wet_scavenging (1/0): precip > 5mm → below-cloud scavenging of PM2.5
#   - avg_boundary_layer_height_m: raw BLH value for scatter vs PM2.5
#   - avg_wind_speed: dispersion proxy
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_quicksight_data_set" "aq_weather_daily" {
  aws_account_id = data.aws_caller_identity.current.account_id
  data_set_id    = "openaq-aq-weather-daily"
  name           = "OpenAQ – AQ + Weather Daily"
  import_mode    = "DIRECT_QUERY"

  physical_table_map {
    physical_table_map_id = "mart-aq-weather-daily"
    relational_table {
      data_source_arn = aws_quicksight_data_source.athena.arn
      catalog         = local.qs_catalog
      schema          = local.qs_schema
      name            = "mart_aq_weather_daily"
      input_columns {
        name = "measurement_date"
        type = "DATETIME"
      }
      input_columns {
        name = "location_id"
        type = "INTEGER"
      }
      input_columns {
        name = "location_name"
        type = "STRING"
      }
      input_columns {
        name = "city"
        type = "STRING"
      }
      input_columns {
        name = "province"
        type = "STRING"
      }
      input_columns {
        name = "sensor_type"
        type = "STRING"
      }
      input_columns {
        name = "avg_pm25"
        type = "DECIMAL"
      }
      input_columns {
        name = "max_pm25"
        type = "DECIMAL"
      }
      input_columns {
        name = "corrected_pm25"
        type = "DECIMAL"
      }
      input_columns {
        name = "aqi_value"
        type = "INTEGER"
      }
      input_columns {
        name = "aqi_category"
        type = "STRING"
      }
      input_columns {
        name = "cigarette_equivalent"
        type = "DECIMAL"
      }
      # Glue type is boolean → QuickSight type must be BIT (not INTEGER)
      input_columns {
        name = "exceeds_who_24h"
        type = "BIT"
      }
      input_columns {
        name = "exceeds_qcvn"
        type = "BIT"
      }
      input_columns {
        name = "avg_temperature_2m"
        type = "DECIMAL"
      }
      input_columns {
        name = "max_temperature_2m"
        type = "DECIMAL"
      }
      input_columns {
        name = "min_temperature_2m"
        type = "DECIMAL"
      }
      input_columns {
        name = "avg_rh_2m"
        type = "DECIMAL"
      }
      input_columns {
        name = "max_rh_2m"
        type = "DECIMAL"
      }
      input_columns {
        name = "min_rh_2m"
        type = "DECIMAL"
      }
      input_columns {
        name = "avg_wind_speed"
        type = "DECIMAL"
      }
      input_columns {
        name = "avg_wind_dir"
        type = "DECIMAL"
      }
      input_columns {
        name = "calm_wind_hours"
        type = "INTEGER"
      }
      input_columns {
        name = "total_precipitation_mm"
        type = "DECIMAL"
      }
      input_columns {
        name = "avg_surface_pressure_hpa"
        type = "DECIMAL"
      }
      input_columns {
        name = "avg_boundary_layer_height_m"
        type = "DECIMAL"
      }
      input_columns {
        name = "min_boundary_layer_height_m"
        type = "DECIMAL"
      }
      input_columns {
        name = "inversion_risk"
        type = "INTEGER"
      }
      input_columns {
        name = "wet_scavenging"
        type = "INTEGER"
      }
    }
  }

  permissions {
    actions   = local.qs_dataset_actions
    principal = local.quicksight_user_arn
  }

  tags = local.common_tags
}


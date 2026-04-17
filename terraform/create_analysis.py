"""
create_analysis.py — Phase 3: Create the Vietnam Air Quality QuickSight analysis.

Usage:
    python create_analysis.py [--dry-run]

Creates (or updates via delete+recreate) the 4-sheet analysis:
  Sheet 1 — Executive Health Scorecard
  Sheet 2 — Seasonal & Weather Drivers
  Sheet 3 — Compliance & Target Trajectory
  Sheet 4 — Forecast Monitor

After creation, exports the definition to quicksight_analysis_definition.json
so it can be imported into Terraform.
"""

import argparse
import json
import os
import sys

import boto3
from botocore.exceptions import ClientError

REGION = "ap-southeast-1"
ANALYSIS_ID = "openaq-air-quality-analysis"
ANALYSIS_NAME = "Vietnam Air Quality Analysis"

# Derive account ID at runtime so this script works for any AWS account.
# The caller must have sts:GetCallerIdentity permission (included in the
# terraform-admin IAM policy granted in Step 5.2).
_sts = boto3.client("sts", region_name=REGION)
ACCOUNT_ID = _sts.get_caller_identity()["Account"]

USER_ARN = (
    f"arn:aws:quicksight:{REGION}:{ACCOUNT_ID}:user/default/terraform-admin"
)

# ── Dataset ARN helper ────────────────────────────────────────────────────────

def ds_arn(ds_id: str) -> str:
    return f"arn:aws:quicksight:{REGION}:{ACCOUNT_ID}:dataset/{ds_id}"


# ── Field helpers ─────────────────────────────────────────────────────────────

def num_dim(field_id: str, ds: str, col: str, *, hier: str | None = None) -> dict:
    """NumericalDimensionField — for INTEGER columns used as category axes."""
    f: dict = {
        "FieldId": field_id,
        "Column": {"DataSetIdentifier": ds, "ColumnName": col},
    }
    if hier:
        f["HierarchyId"] = hier
    return {"NumericalDimensionField": f}


def cat_dim(field_id: str, ds: str, col: str) -> dict:
    """CategoricalDimensionField — for STRING columns."""
    return {
        "CategoricalDimensionField": {
            "FieldId": field_id,
            "Column": {"DataSetIdentifier": ds, "ColumnName": col},
        }
    }


def date_dim(field_id: str, ds: str, col: str, gran: str = "DAY") -> dict:
    """DateDimensionField — for DATETIME columns.
    HierarchyId is set to field_id so callers can auto-generate DateTimeHierarchy."""
    return {
        "DateDimensionField": {
            "FieldId": field_id,
            "Column": {"DataSetIdentifier": ds, "ColumnName": col},
            "DateGranularity": gran,
            "HierarchyId": field_id,
        }
    }


def date_hierarchy(field_id: str) -> dict:
    """DateTimeHierarchy entry for ColumnHierarchies, keyed by field_id."""
    return {
        "DateTimeHierarchy": {
            "HierarchyId": field_id,
            "DrillDownFilters": [],
        }
    }


def num_meas(field_id: str, ds: str, col: str, agg: str = "SUM") -> dict:
    """NumericalMeasureField — for DECIMAL/INTEGER measure values."""
    return {
        "NumericalMeasureField": {
            "FieldId": field_id,
            "Column": {"DataSetIdentifier": ds, "ColumnName": col},
            "AggregationFunction": {"SimpleNumericalAggregation": agg},
        }
    }


def title(text: str) -> dict:
    return {
        "Visibility": "VISIBLE",
        "FormatText": {"PlainText": text},
    }


def ref_line_val(val: float, label: str, color: str = "#D13212") -> dict:
    return {
        "Status": "ENABLED",
        "DataConfiguration": {"StaticConfiguration": {"Value": val}},
        "LabelConfiguration": {
            "ValueLabelConfiguration": {
                "RelativePosition": "BEFORE_CUSTOM_LABEL",
                "FormatConfiguration": {
                    "NumberDisplayFormatConfiguration": {
                        "DecimalPlacesConfiguration": {"DecimalPlaces": 0},
                    }
                },
            },
            "CustomLabelConfiguration": {"CustomLabel": label},
        },
        "StyleConfiguration": {
            "Pattern": "DASHED",
            "Color": color,
        },
    }


# ── Visual builders ───────────────────────────────────────────────────────────

def kpi_visual(
    vid: str,
    ttl: str,
    ds: str,
    val_col: str,
    val_agg: str = "AVERAGE",
    trend_col: str | None = None,
    trend_ds: str | None = None,
) -> dict:
    values = [num_meas(f"{vid}-v", ds, val_col, val_agg)]
    trend = []
    if trend_col:
        trend = [cat_dim(f"{vid}-t", trend_ds or ds, trend_col)]
    return {
        "KPIVisual": {
            "VisualId": vid,
            "Title": title(ttl),
            "Subtitle": {"Visibility": "HIDDEN"},
            "ChartConfiguration": {
                "FieldWells": {
                    "Values": values,
                    "TrendGroups": trend,
                    "TargetValues": [],
                },
                "KPIOptions": {
                    "ProgressBar": {"Visibility": "HIDDEN"},
                    "TrendArrows": {"Visibility": "VISIBLE"},
                    "SecondaryValue": {"Visibility": "VISIBLE"},
                    "PrimaryValueDisplayType": "ACTUAL",
                },
            },
            "Actions": [],
            "ColumnHierarchies": [],
        }
    }


def bar_visual(
    vid: str,
    ttl: str,
    ds: str,
    *,
    category_fields: list,
    value_fields: list,
    color_fields: list | None = None,
    arrangement: str = "CLUSTERED",
    orientation: str = "VERTICAL",
    ref_lines: list | None = None,
) -> dict:
    return {
        "BarChartVisual": {
            "VisualId": vid,
            "Title": title(ttl),
            "Subtitle": {"Visibility": "HIDDEN"},
            "ChartConfiguration": {
                "FieldWells": {
                    "BarChartAggregatedFieldWells": {
                        "Category": category_fields,
                        "Values": value_fields,
                        "Colors": color_fields or [],
                        "SmallMultiples": [],
                    }
                },
                "Orientation": orientation,
                "BarsArrangement": arrangement,
                "ReferenceLines": ref_lines or [],
            },
            "Actions": [],
            "ColumnHierarchies": [],
        }
    }


def line_visual(
    vid: str,
    ttl: str,
    ds: str,
    *,
    category_fields: list,
    value_fields: list,
    color_fields: list | None = None,
    ref_lines: list | None = None,
    line_type: str = "LINE",
) -> dict:
    return {
        "LineChartVisual": {
            "VisualId": vid,
            "Title": title(ttl),
            "Subtitle": {"Visibility": "HIDDEN"},
            "ChartConfiguration": {
                "FieldWells": {
                    "LineChartAggregatedFieldWells": {
                        "Category": category_fields,
                        "Values": value_fields,
                        "Colors": color_fields or [],
                        "SmallMultiples": [],
                    }
                },
                "Type": line_type,
                "ReferenceLines": ref_lines or [],
            },
            "Actions": [],
            "ColumnHierarchies": [],
        }
    }


def heatmap_visual(
    vid: str,
    ttl: str,
    ds: str,
    *,
    row_fields: list,
    col_fields: list,
    val_fields: list,
) -> dict:
    return {
        "HeatMapVisual": {
            "VisualId": vid,
            "Title": title(ttl),
            "Subtitle": {"Visibility": "HIDDEN"},
            "ChartConfiguration": {
                "FieldWells": {
                    "HeatMapAggregatedFieldWells": {
                        "Rows": row_fields,
                        "Columns": col_fields,
                        "Values": val_fields,
                    }
                },
                "SortConfiguration": {
                    "HeatMapRowSort": [],
                    "HeatMapColumnSort": [],
                    "HeatMapRowItemsLimitConfiguration": {"OtherCategories": "EXCLUDE"},
                    "HeatMapColumnItemsLimitConfiguration": {"OtherCategories": "EXCLUDE"},
                },
                "ColorScale": {
                    "Colors": [
                        {"Color": "#1A9641"},  # green  – low PM2.5
                        {"Color": "#FFFFBF"},  # yellow – moderate
                        {"Color": "#D7191C"},  # red    – high PM2.5
                    ],
                    "ColorFillType": "GRADIENT",
                    "NullValueColor": {"Color": "#D9D9D9"},
                },
            },
            "Actions": [],
            "ColumnHierarchies": [],
        }
    }


def scatter_visual(
    vid: str,
    ttl: str,
    ds: str,
    *,
    x_fields: list,
    y_fields: list,
    group_fields: list | None = None,
    size_fields: list | None = None,
) -> dict:
    return {
        "ScatterPlotVisual": {
            "VisualId": vid,
            "Title": title(ttl),
            "Subtitle": {"Visibility": "HIDDEN"},
            "ChartConfiguration": {
                "FieldWells": {
                    "ScatterPlotCategoricallyAggregatedFieldWells": {
                        "XAxis": x_fields,
                        "YAxis": y_fields,
                        "Category": group_fields or [],
                        "Size": size_fields or [],
                        "Label": [],
                    }
                },
                "SortConfiguration": {},
            },
            "Actions": [],
            "ColumnHierarchies": [],
        }
    }


# ── Filter control builders ───────────────────────────────────────────────────

def dropdown_filter(ctrl_id: str, title_text: str, ds: str, col: str) -> dict:
    return {
        "Dropdown": {
            "FilterControlId": ctrl_id,
            "Title": title_text,
            "SourceFilterId": f"filter-{ctrl_id}",
            "DisplayOptions": {
                "SelectAllOptions": {"Visibility": "VISIBLE"},
                "TitleOptions": {"Visibility": "VISIBLE", "FontConfiguration": {}},
            },
            "Type": "MULTI_SELECT",
        }
    }


def filter_group(
    fg_id: str,
    ctrl_id: str,
    ds: str,
    col: str,
    scope_sheet: str,
) -> dict:
    return {
        "FilterGroupId": fg_id,
        "Filters": [
            {
                "CategoryFilter": {
                    "FilterId": f"filter-{ctrl_id}",
                    "Column": {
                        "DataSetIdentifier": ds,
                        "ColumnName": col,
                    },
                    "Configuration": {
                        "FilterListConfiguration": {
                            "MatchOperator": "CONTAINS",
                            "SelectAllOptions": "FILTER_ALL_VALUES",
                        }
                    },
                }
            }
        ],
        "ScopeConfiguration": {
            "SelectedSheets": {
                "SheetVisualScopingConfigurations": [
                    {
                        "SheetId": scope_sheet,
                        "Scope": "ALL_VISUALS",
                    }
                ]
            }
        },
        "CrossDataset": "SINGLE_DATASET",
        "Status": "ENABLED",
    }


# ── Sheet builders ────────────────────────────────────────────────────────────

def build_sheet1() -> dict:
    """Executive Health Scorecard — city officials, media, public health."""
    sid = "sheet-1"
    hs = "health-summary"
    da = "daily-aqi"
    am = "annual-monthly-trend"

    visuals = [
        # Row 1 — Hero KPIs
        kpi_visual("s1-kpi-cigarette", "Cigarettes/Day Equivalent (Annual Avg)",
                   hs, "avg_cigarette_equivalent", "AVERAGE"),
        kpi_visual("s1-kpi-who-compliance", "WHO Compliance Rate (%)",
                   hs, "who_compliance_pct", "AVERAGE"),
        kpi_visual("s1-kpi-avg-pm25", "Annual Mean PM2.5 (µg/m³)",
                   hs, "avg_pm25", "AVERAGE"),
        kpi_visual("s1-kpi-unhealthy-days", "Unhealthy+ Days (AQI > 150)",
                   hs, "unhealthy_days", "SUM"),
        kpi_visual("s1-kpi-hazardous-days", "Hazardous Days",
                   hs, "hazardous_days", "SUM"),

        # Row 2 — Annual health day stacked bar (city = X axis, day types = stack)
        bar_visual(
            "s1-bar-health-days",
            "Health Day Breakdown by City (Stacked) — Good/Moderate/USG/Unhealthy+",
            hs,
            category_fields=[
                cat_dim("s1-bar-hd-city", hs, "city"),
            ],
            value_fields=[
                num_meas("s1-bar-hd-good",    hs, "good_days",           "SUM"),
                num_meas("s1-bar-hd-mod",     hs, "moderate_days",       "SUM"),
                num_meas("s1-bar-hd-usg",     hs, "usg_days",            "SUM"),
                num_meas("s1-bar-hd-unheal",  hs, "unhealthy_days",      "SUM"),
                num_meas("s1-bar-hd-vunheal", hs, "very_unhealthy_days", "SUM"),
                num_meas("s1-bar-hd-haz",     hs, "hazardous_days",      "SUM"),
            ],
            arrangement="STACKED",
        ),

        # Row 3 — Annual PM2.5 trend line by city
        line_visual(
            "s1-line-pm25-trend",
            "Annual Mean PM2.5 Trend by City (µg/m³)",
            am,
            category_fields=[num_dim("s1-ln-year", am, "year")],
            value_fields=[num_meas("s1-ln-pm25", am, "avg_pm25", "AVERAGE")],
            color_fields=[cat_dim("s1-ln-city", am, "city")],
            ref_lines=[
                ref_line_val(40.0,  "2030 Target: 40 µg/m³", "#E07B39"),
                ref_line_val(15.0,  "WHO AQG: 15 µg/m³",    "#D13212"),
            ],
        ),

        # Row 4 — WHO exceedance rate trend (from annual_monthly_trend)
        line_visual(
            "s1-line-who-exc",
            "Annual WHO Exceedance Rate (%) — City Trend",
            am,
            category_fields=[num_dim("s1-we-year", am, "year")],
            value_fields=[num_meas("s1-we-rate", am, "who_exceedance_rate", "AVERAGE")],
            color_fields=[cat_dim("s1-we-city", am, "city")],
        ),
    ]

    filter_controls = [
        dropdown_filter("s1-fc-city", "City", hs, "city"),
    ]

    return {
        "SheetId": sid,
        "Name": "Executive Health Scorecard",
        "Visuals": visuals,
        "FilterControls": filter_controls,
        "Layouts": [
            {
                "Configuration": {
                    "GridLayout": {
                        "Elements": [
                            # Row 1: 5 KPIs
                            {"ElementId": "s1-kpi-cigarette",     "ElementType": "VISUAL", "ColumnIndex": 0,  "ColumnSpan": 7,  "RowIndex": 0, "RowSpan": 6},
                            {"ElementId": "s1-kpi-who-compliance", "ElementType": "VISUAL", "ColumnIndex": 7,  "ColumnSpan": 7,  "RowIndex": 0, "RowSpan": 6},
                            {"ElementId": "s1-kpi-avg-pm25",       "ElementType": "VISUAL", "ColumnIndex": 14, "ColumnSpan": 7,  "RowIndex": 0, "RowSpan": 6},
                            {"ElementId": "s1-kpi-unhealthy-days", "ElementType": "VISUAL", "ColumnIndex": 21, "ColumnSpan": 7,  "RowIndex": 0, "RowSpan": 6},
                            {"ElementId": "s1-kpi-hazardous-days", "ElementType": "VISUAL", "ColumnIndex": 28, "ColumnSpan": 8,  "RowIndex": 0, "RowSpan": 6},
                            # Row 2: stacked bar full width
                            {"ElementId": "s1-bar-health-days",   "ElementType": "VISUAL", "ColumnIndex": 0,  "ColumnSpan": 36, "RowIndex": 6, "RowSpan": 12},
                            # Row 3: PM2.5 trend + WHO exceedance
                            {"ElementId": "s1-line-pm25-trend",   "ElementType": "VISUAL", "ColumnIndex": 0,  "ColumnSpan": 18, "RowIndex": 18, "RowSpan": 12},
                            {"ElementId": "s1-line-who-exc",      "ElementType": "VISUAL", "ColumnIndex": 18, "ColumnSpan": 18, "RowIndex": 18, "RowSpan": 12},
                        ],
                        "CanvasSizeOptions": {"ScreenCanvasSizeOptions": {"ResizeOption": "RESPONSIVE"}},
                    }
                }
            }
        ],
    }


def build_sheet2() -> dict:
    """Seasonal & Weather Drivers."""
    sid = "sheet-2"
    mp  = "monthly-profile"
    dp  = "diurnal-profile"
    wd  = "aq-weather-daily"
    pr  = "pollutant-ratio"

    who_ref  = ref_line_val(15.0, "WHO 24h: 15 µg/m³", "#D13212")
    qcvn_ref = ref_line_val(50.0, "QCVN: 50 µg/m³",   "#E07B39")

    visuals = [
        # Panel A — Seasonal rhythm
        bar_visual(
            "s2-bar-monthly",
            "Monthly PM2.5 Profile (µg/m³) — Seasonal Rhythm",
            mp,
            category_fields=[num_dim("s2-bm-mon", mp, "month_of_year")],
            value_fields=[num_meas("s2-bm-val", mp, "avg_value", "AVERAGE")],
            color_fields=[cat_dim("s2-bm-city", mp, "city")],
            arrangement="CLUSTERED",
            ref_lines=[who_ref, qcvn_ref],
        ),
        line_visual(
            "s2-line-diurnal",
            "Diurnal PM2.5 Pattern by Hour (UTC+7) — Hanoi vs HCMC",
            dp,
            category_fields=[num_dim("s2-ld-hr", dp, "hour_of_day")],
            value_fields=[num_meas("s2-ld-val", dp, "avg_value", "AVERAGE")],
            color_fields=[cat_dim("s2-ld-city", dp, "city")],
        ),

        # Panel B — Weather drivers
        bar_visual(
            "s2-bar-inversion",
            "Avg PM2.5 by Inversion Risk (0=Dispersed, 1=Trapped)",
            wd,
            category_fields=[num_dim("s2-bi-inv", wd, "inversion_risk")],
            value_fields=[num_meas("s2-bi-pm25", wd, "avg_pm25", "AVERAGE")],
            color_fields=[cat_dim("s2-bi-city", wd, "city")],
            arrangement="CLUSTERED",
        ),
        bar_visual(
            "s2-bar-wetscav",
            "Avg PM2.5 by Wet Scavenging (0=Dry, 1=Rain-Washed)",
            wd,
            category_fields=[num_dim("s2-bw-wet", wd, "wet_scavenging")],
            value_fields=[num_meas("s2-bw-pm25", wd, "avg_pm25", "AVERAGE")],
            color_fields=[cat_dim("s2-bw-city", wd, "city")],
            arrangement="CLUSTERED",
        ),
        # Wind speed vs PM2.5 — shown as dual-axis bar (avg_wind_speed + avg_pm25 by city)
        bar_visual(
            "s2-bar-wind-pm25",
            "Avg Wind Speed & PM2.5 by City — Dispersion vs Pollution",
            wd,
            category_fields=[cat_dim("s2-sw-city", wd, "city")],
            value_fields=[
                num_meas("s2-sw-wind", wd, "avg_wind_speed", "AVERAGE"),
                num_meas("s2-sw-pm25", wd, "avg_pm25",       "AVERAGE"),
            ],
            arrangement="CLUSTERED",
        ),

        # Panel C — Source attribution
        bar_visual(
            "s2-bar-pm-ratio",
            "PM2.5/PM10 Ratio by City — Source Attribution",
            pr,
            category_fields=[cat_dim("s2-pr-city", pr, "city")],
            value_fields=[num_meas("s2-pr-ratio", pr, "pm25_pm10_ratio", "AVERAGE")],
            color_fields=[cat_dim("s2-pr-src", pr, "source_indicator")],
            arrangement="CLUSTERED",
        ),

        # Panel D — Wind direction sector vs PM2.5
        # wind_sector is a calculated field (defined in build_definition):
        #   NE (0-90)  = continental dry-season flow from China/Yunnan -> high PM
        #   SW (180-270) = maritime monsoon -> clean air
        bar_visual(
            "s2-bar-wind-sector",
            "Avg PM2.5 by Wind Direction Sector — Continental vs Maritime Flow",
            wd,
            category_fields=[cat_dim("s2-ws-sector", wd, "wind_sector")],
            value_fields=[num_meas("s2-ws-pm25", wd, "avg_pm25", "AVERAGE")],
            color_fields=[cat_dim("s2-ws-city", wd, "city")],
            arrangement="CLUSTERED",
        ),

        # Panel D2 — Corrected vs raw PM2.5 monthly trend
        # Exposes the magnitude of humidity-driven sensor bias over time.
        # Uses inline dict (required when date_dim sets HierarchyId — the
        # line_visual helper must declare ColumnHierarchies to match).
        {
            "LineChartVisual": {
                "VisualId": "s2-line-corr-vs-raw",
                "Title": title("Corrected vs Raw PM2.5 Monthly Average (µg/m³) — Sensor Bias"),
                "Subtitle": {"Visibility": "HIDDEN"},
                "ChartConfiguration": {
                    "FieldWells": {
                        "LineChartAggregatedFieldWells": {
                            "Category": [date_dim("s2-cr-date", wd, "measurement_date", "MONTH")],
                            "Values": [
                                num_meas("s2-cr-raw",  wd, "avg_pm25",       "AVERAGE"),
                                num_meas("s2-cr-corr", wd, "corrected_pm25", "AVERAGE"),
                            ],
                            "Colors": [],
                            "SmallMultiples": [],
                        }
                    },
                    "Type": "LINE",
                    "ReferenceLines": [],
                },
                "Actions": [],
                "ColumnHierarchies": [date_hierarchy("s2-cr-date")],
            }
        },

        # Panel E — Relative humidity vs PM2.5 monthly time series
        # High RH (>80%) drives hygroscopic PM2.5 growth (+30-60% measured mass).
        # Seasonal co-variation of RH and PM2.5 reveals humidity-driven episodes.
        # (Scatter replaced with line: scatter visuals are unreliable via the API.)
        {
            "LineChartVisual": {
                "VisualId": "s2-line-rh-pm25",
                "Title": title("Relative Humidity & PM2.5 Monthly Trend — Hygroscopic Growth"),
                "Subtitle": {"Visibility": "HIDDEN"},
                "ChartConfiguration": {
                    "FieldWells": {
                        "LineChartAggregatedFieldWells": {
                            "Category": [date_dim("s2-rh-date", wd, "measurement_date", "MONTH")],
                            "Values": [
                                num_meas("s2-rh-rh",   wd, "avg_rh_2m", "AVERAGE"),
                                num_meas("s2-rh-pm25", wd, "avg_pm25",  "AVERAGE"),
                            ],
                            "Colors": [],
                            "SmallMultiples": [],
                        }
                    },
                    "Type": "LINE",
                    "ReferenceLines": [],
                },
                "Actions": [],
                "ColumnHierarchies": [date_hierarchy("s2-rh-date")],
            }
        },

        # Panel F — Surface pressure vs PM2.5 monthly time series
        # High pressure (>1015 hPa) = anticyclone subsidence = suppressed BLH = stagnant air.
        # (Scatter replaced with line: scatter visuals are unreliable via the API.)
        {
            "LineChartVisual": {
                "VisualId": "s2-line-pressure-pm25",
                "Title": title("Surface Pressure & PM2.5 Monthly Trend — Anticyclone Episodes"),
                "Subtitle": {"Visibility": "HIDDEN"},
                "ChartConfiguration": {
                    "FieldWells": {
                        "LineChartAggregatedFieldWells": {
                            "Category": [date_dim("s2-sp-date", wd, "measurement_date", "MONTH")],
                            "Values": [
                                num_meas("s2-sp-hpa",  wd, "avg_surface_pressure_hpa", "AVERAGE"),
                                num_meas("s2-sp-pm25", wd, "avg_pm25",                 "AVERAGE"),
                            ],
                            "Colors": [],
                            "SmallMultiples": [],
                        }
                    },
                    "Type": "LINE",
                    "ReferenceLines": [],
                },
                "Actions": [],
                "ColumnHierarchies": [date_hierarchy("s2-sp-date")],
            }
        },

        # Panel G — Calm wind hours by month (stagnation climatology)
        # Uses inline dict to declare ColumnHierarchies for the date field.
        {
            "BarChartVisual": {
                "VisualId": "s2-bar-calm-wind",
                "Title": title("Avg Calm-Wind Hours per Day by Month (wind < 1 m/s) — Stagnation Climatology"),
                "Subtitle": {"Visibility": "HIDDEN"},
                "ChartConfiguration": {
                    "FieldWells": {
                        "BarChartAggregatedFieldWells": {
                            "Category": [date_dim("s2-cw-date", wd, "measurement_date", "MONTH")],
                            "Values": [num_meas("s2-cw-hrs", wd, "calm_wind_hours", "AVERAGE")],
                            "Colors": [cat_dim("s2-cw-city", wd, "city")],
                            "SmallMultiples": [],
                        }
                    },
                    "Orientation": "VERTICAL",
                    "BarsArrangement": "CLUSTERED",
                    "ReferenceLines": [],
                },
                "Actions": [],
                "ColumnHierarchies": [date_hierarchy("s2-cw-date")],
            }
        },
    ]

    filter_controls = [
        dropdown_filter("s2-fc-city",   "City",   mp, "city"),
        dropdown_filter("s2-fc-season", "Season", mp, "season"),
    ]

    return {
        "SheetId": sid,
        "Name": "Seasonal & Weather Drivers",
        "Visuals": visuals,
        "FilterControls": filter_controls,
        "Layouts": [
            {
                "Configuration": {
                    "GridLayout": {
                        "Elements": [
                            # Row 1: monthly bar + diurnal line
                            {"ElementId": "s2-bar-monthly",  "ElementType": "VISUAL", "ColumnIndex": 0,  "ColumnSpan": 18, "RowIndex": 0, "RowSpan": 12},
                            {"ElementId": "s2-line-diurnal", "ElementType": "VISUAL", "ColumnIndex": 18, "ColumnSpan": 18, "RowIndex": 0, "RowSpan": 12},
                            # Row 2: inversion + wet scavenging + wind/pm25 dual bar
                            {"ElementId": "s2-bar-inversion",  "ElementType": "VISUAL", "ColumnIndex": 0,  "ColumnSpan": 12, "RowIndex": 12, "RowSpan": 11},
                            {"ElementId": "s2-bar-wetscav",    "ElementType": "VISUAL", "ColumnIndex": 12, "ColumnSpan": 12, "RowIndex": 12, "RowSpan": 11},
                            {"ElementId": "s2-bar-wind-pm25",  "ElementType": "VISUAL", "ColumnIndex": 24, "ColumnSpan": 12, "RowIndex": 12, "RowSpan": 11},
                            # Row 3: PM ratio (source attribution)
                            {"ElementId": "s2-bar-pm-ratio", "ElementType": "VISUAL", "ColumnIndex": 0,  "ColumnSpan": 36, "RowIndex": 23, "RowSpan": 10},
                            # Row 4: wind sector + corrected-vs-raw + calm wind hours
                            {"ElementId": "s2-bar-wind-sector",   "ElementType": "VISUAL", "ColumnIndex": 0,  "ColumnSpan": 12, "RowIndex": 33, "RowSpan": 11},
                            {"ElementId": "s2-line-corr-vs-raw",  "ElementType": "VISUAL", "ColumnIndex": 12, "ColumnSpan": 12, "RowIndex": 33, "RowSpan": 11},
                            {"ElementId": "s2-bar-calm-wind",     "ElementType": "VISUAL", "ColumnIndex": 24, "ColumnSpan": 12, "RowIndex": 33, "RowSpan": 11},
                            # Row 5: RH monthly trend + surface pressure monthly trend
                            {"ElementId": "s2-line-rh-pm25",       "ElementType": "VISUAL", "ColumnIndex": 0,  "ColumnSpan": 18, "RowIndex": 44, "RowSpan": 11},
                            {"ElementId": "s2-line-pressure-pm25", "ElementType": "VISUAL", "ColumnIndex": 18, "ColumnSpan": 18, "RowIndex": 44, "RowSpan": 11},
                        ],
                        "CanvasSizeOptions": {"ScreenCanvasSizeOptions": {"ResizeOption": "RESPONSIVE"}},
                    }
                }
            }
        ],
    }


def build_sheet3() -> dict:
    """Compliance & Target Trajectory."""
    sid = "sheet-3"
    es  = "exceedance-stats"
    am  = "annual-monthly-trend"

    who_20_ref = ref_line_val(20.0, "Target ≤ 20%", "#E07B39")

    visuals = [
        # WHO exceedance trend
        line_visual(
            "s3-line-who-exc",
            "WHO PM2.5 Exceedance Rate (%) — Annual Trend by City",
            es,
            category_fields=[num_dim("s3-we-year", es, "year")],
            value_fields=[num_meas("s3-we-rate", es, "who_exceedance_rate", "AVERAGE")],
            color_fields=[cat_dim("s3-we-city", es, "city")],
            ref_lines=[who_20_ref],
        ),

        # QCVN exceedance trend
        line_visual(
            "s3-line-qcvn-exc",
            "QCVN Exceedance Rate (%) — Annual Trend by City",
            es,
            category_fields=[num_dim("s3-qe-year", es, "year")],
            value_fields=[num_meas("s3-qe-rate", es, "qcvn_exceedance_rate", "AVERAGE")],
            color_fields=[cat_dim("s3-qe-city", es, "city")],
        ),

        # Year-over-year monthly heatmap (city × year rows, month columns)
        heatmap_visual(
            "s3-heatmap-yoy",
            "Year-over-Year Monthly PM2.5 Heatmap (µg/m³) — Hanoi",
            am,
            row_fields=[num_dim("s3-hm-year", am, "year")],
            col_fields=[num_dim("s3-hm-mon",  am, "month_of_year")],
            val_fields=[num_meas("s3-hm-pm25", am, "avg_pm25", "AVERAGE")],
        ),

        # p95 episode severity bar by year × month
        bar_visual(
            "s3-bar-p95",
            "p95 PM2.5 Episode Severity by Month (µg/m³) — Worst-Day Trend",
            es,
            category_fields=[num_dim("s3-p95-mon", es, "month_of_year")],
            value_fields=[num_meas("s3-p95-val", es, "p95_pm25", "AVERAGE")],
            color_fields=[cat_dim("s3-p95-city", es, "city")],
            arrangement="CLUSTERED",
            ref_lines=[
                ref_line_val(15.0, "WHO 15 µg/m³",  "#D13212"),
                ref_line_val(50.0, "QCVN 50 µg/m³", "#E07B39"),
            ],
        ),

        # WHO vs QCVN exceedance split stacked bar — regulatory framing.
        # Uses calculated fields (defined in build_definition):
        #   compliant_days  = total_days - who_exceedance_days
        #   who_only_days   = who_exceedance_days - qcvn_exceedance_days
        #   qcvn_exceedance_days (raw column)
        # Three stacked segments: Compliant / WHO-only / Also QCVN
        # Shows how far above the Vietnamese legal standard the city sits vs WHO.
        bar_visual(
            "s3-bar-exceedance-split",
            "Annual Day Count: Compliant / WHO-Only Exceedance / Also QCVN Exceedance",
            es,
            category_fields=[num_dim("s3-sp-year", es, "year")],
            value_fields=[
                num_meas("s3-sp-comp",   es, "compliant_days",      "SUM"),
                num_meas("s3-sp-who",    es, "who_only_days",        "SUM"),
                num_meas("s3-sp-qcvn",   es, "qcvn_exceedance_days", "SUM"),
            ],
            arrangement="STACKED",
        ),
    ]

    filter_controls = [
        dropdown_filter("s3-fc-city", "City", es, "city"),
        dropdown_filter("s3-fc-year", "Year", es, "year"),
    ]

    return {
        "SheetId": sid,
        "Name": "Compliance & Target Trajectory",
        "Visuals": visuals,
        "FilterControls": filter_controls,
        "Layouts": [
            {
                "Configuration": {
                    "GridLayout": {
                        "Elements": [
                            # Row 1: WHO + QCVN exceedance trend lines
                            {"ElementId": "s3-line-who-exc",  "ElementType": "VISUAL", "ColumnIndex": 0,  "ColumnSpan": 18, "RowIndex": 0, "RowSpan": 12},
                            {"ElementId": "s3-line-qcvn-exc", "ElementType": "VISUAL", "ColumnIndex": 18, "ColumnSpan": 18, "RowIndex": 0, "RowSpan": 12},
                            # Row 2: YoY heatmap + p95 episode severity
                            {"ElementId": "s3-heatmap-yoy",  "ElementType": "VISUAL", "ColumnIndex": 0,  "ColumnSpan": 18, "RowIndex": 12, "RowSpan": 12},
                            {"ElementId": "s3-bar-p95",       "ElementType": "VISUAL", "ColumnIndex": 18, "ColumnSpan": 18, "RowIndex": 12, "RowSpan": 12},
                            # Row 3: WHO vs QCVN regulatory split (full width)
                            {"ElementId": "s3-bar-exceedance-split", "ElementType": "VISUAL", "ColumnIndex": 0, "ColumnSpan": 36, "RowIndex": 24, "RowSpan": 11},
                        ],
                        "CanvasSizeOptions": {"ScreenCanvasSizeOptions": {"ResizeOption": "RESPONSIVE"}},
                    }
                }
            }
        ],
    }


def build_sheet4() -> dict:
    """Forecast Monitor."""
    sid = "sheet-4"
    fa  = "forecast-accuracy"

    who_ref  = ref_line_val(15.0, "WHO AQG: 15 µg/m³", "#D13212")
    qcvn_ref = ref_line_val(50.0, "QCVN: 50 µg/m³",   "#E07B39")
    rmse_ref = ref_line_val(25.0, "Alarm: 25 µg/m³",   "#D13212")

    visuals = [
        # KPIs — holdout RMSE per model
        kpi_visual("s4-kpi-rmse-sarima",  "SARIMA Holdout RMSE (µg/m³)",  fa, "holdout_rmse", "AVERAGE"),
        kpi_visual("s4-kpi-rmse-prophet", "Prophet Holdout RMSE (µg/m³)", fa, "holdout_rmse", "AVERAGE"),
        kpi_visual("s4-kpi-rolling-rmse", "Rolling RMSE 30d (µg/m³)",    fa, "rolling_rmse_30d", "AVERAGE"),
        kpi_visual("s4-kpi-bias",         "Rolling Bias 30d (µg/m³)",     fa, "rolling_bias_30d", "AVERAGE"),

        # 7-day SARIMA forecast line with CI context
        # When color is present, only one value is allowed
        {
            "LineChartVisual": {
                "VisualId": "s4-line-forecast",
                "Title": title("7-Day PM2.5 Forecast by Model"),
                "Subtitle": {"Visibility": "HIDDEN"},
                "ChartConfiguration": {
                    "FieldWells": {
                        "LineChartAggregatedFieldWells": {
                            "Category": [date_dim("s4-lf-date", fa, "forecast_date", "DAY")],
                            "Values": [num_meas("s4-lf-fc", fa, "forecast_pm25", "AVERAGE")],
                            "Colors": [cat_dim("s4-lf-model", fa, "model")],
                            "SmallMultiples": [],
                        }
                    },
                    "Type": "LINE",
                    "ReferenceLines": [who_ref, qcvn_ref],
                },
                "Actions": [],
                "ColumnHierarchies": [date_hierarchy("s4-lf-date")],
            }
        },
        # CI band — separate visual without color dimension
        {
            "LineChartVisual": {
                "VisualId": "s4-line-ci",
                "Title": title("Forecast 95% CI Bounds (Lower / Upper)"),
                "Subtitle": {"Visibility": "HIDDEN"},
                "ChartConfiguration": {
                    "FieldWells": {
                        "LineChartAggregatedFieldWells": {
                            "Category": [date_dim("s4-ci-date", fa, "forecast_date", "DAY")],
                            "Values": [
                                num_meas("s4-ci-low",  fa, "ci_lower_95", "AVERAGE"),
                                num_meas("s4-ci-high", fa, "ci_upper_95", "AVERAGE"),
                            ],
                            "Colors": [],
                            "SmallMultiples": [],
                        }
                    },
                    "Type": "LINE",
                    "ReferenceLines": [],
                },
                "Actions": [],
                "ColumnHierarchies": [date_hierarchy("s4-ci-date")],
            }
        },

        # Forecast vs actual grouped bar (replaces scatter — more reliable via API)
        bar_visual(
            "s4-scatter-fcvact",
            "Actual vs Forecast PM2.5 by Model — Bias Diagnostic",
            fa,
            category_fields=[cat_dim("s4-sv-model", fa, "model")],
            value_fields=[
                num_meas("s4-sv-act", fa, "actual_pm25",   "AVERAGE"),
                num_meas("s4-sv-fc",  fa, "forecast_pm25", "AVERAGE"),
            ],
            arrangement="CLUSTERED",
        ),

        # Rolling RMSE 30d trend
        {
            "LineChartVisual": {
                "VisualId": "s4-line-rolling-rmse",
                "Title": title("Rolling RMSE 30d — Model Skill Over Time"),
                "Subtitle": {"Visibility": "HIDDEN"},
                "ChartConfiguration": {
                    "FieldWells": {
                        "LineChartAggregatedFieldWells": {
                            "Category": [date_dim("s4-rr-date", fa, "forecast_date", "DAY")],
                            "Values": [num_meas("s4-rr-rmse", fa, "rolling_rmse_30d", "AVERAGE")],
                            "Colors": [cat_dim("s4-rr-model", fa, "model")],
                            "SmallMultiples": [],
                        }
                    },
                    "Type": "LINE",
                    "ReferenceLines": [rmse_ref],
                },
                "Actions": [],
                "ColumnHierarchies": [date_hierarchy("s4-rr-date")],
            }
        },

        # RMSE comparison bar by model × city
        bar_visual(
            "s4-bar-rmse-model",
            "Holdout RMSE by Model & Station — SARIMA vs Prophet",
            fa,
            category_fields=[cat_dim("s4-bm-loc", fa, "location_name")],
            value_fields=[num_meas("s4-bm-rmse", fa, "holdout_rmse", "AVERAGE")],
            color_fields=[cat_dim("s4-bm-model", fa, "model")],
            arrangement="CLUSTERED",
            ref_lines=[rmse_ref],
        ),
    ]

    filter_controls = [
        dropdown_filter("s4-fc-loc",   "Station",  fa, "location_name"),
        dropdown_filter("s4-fc-model", "Model",    fa, "model"),
    ]

    return {
        "SheetId": sid,
        "Name": "Forecast Monitor",
        "Visuals": visuals,
        "FilterControls": filter_controls,
        "Layouts": [
            {
                "Configuration": {
                    "GridLayout": {
                        "Elements": [
                            # Row 1: 4 KPIs
                            {"ElementId": "s4-kpi-rmse-sarima",  "ElementType": "VISUAL", "ColumnIndex": 0,  "ColumnSpan": 9,  "RowIndex": 0, "RowSpan": 6},
                            {"ElementId": "s4-kpi-rmse-prophet", "ElementType": "VISUAL", "ColumnIndex": 9,  "ColumnSpan": 9,  "RowIndex": 0, "RowSpan": 6},
                            {"ElementId": "s4-kpi-rolling-rmse", "ElementType": "VISUAL", "ColumnIndex": 18, "ColumnSpan": 9,  "RowIndex": 0, "RowSpan": 6},
                            {"ElementId": "s4-kpi-bias",         "ElementType": "VISUAL", "ColumnIndex": 27, "ColumnSpan": 9,  "RowIndex": 0, "RowSpan": 6},
                            # Row 2: forecast line + CI bounds
                            {"ElementId": "s4-line-forecast",    "ElementType": "VISUAL", "ColumnIndex": 0,  "ColumnSpan": 18, "RowIndex": 6, "RowSpan": 12},
                            {"ElementId": "s4-line-ci",          "ElementType": "VISUAL", "ColumnIndex": 18, "ColumnSpan": 18, "RowIndex": 6, "RowSpan": 12},
                            # Row 3: actual vs forecast scatter + rolling RMSE + RMSE bar
                            {"ElementId": "s4-scatter-fcvact",   "ElementType": "VISUAL", "ColumnIndex": 0,  "ColumnSpan": 12, "RowIndex": 18, "RowSpan": 11},
                            {"ElementId": "s4-line-rolling-rmse","ElementType": "VISUAL", "ColumnIndex": 12, "ColumnSpan": 12, "RowIndex": 18, "RowSpan": 11},
                            {"ElementId": "s4-bar-rmse-model",   "ElementType": "VISUAL", "ColumnIndex": 24, "ColumnSpan": 12, "RowIndex": 18, "RowSpan": 11},
                        ],
                        "CanvasSizeOptions": {"ScreenCanvasSizeOptions": {"ResizeOption": "RESPONSIVE"}},
                    }
                }
            }
        ],
    }


# ── Filter group definitions (applied at analysis level) ─────────────────────

def build_filter_groups() -> list:
    return [
        # Sheet 1 — city filter on health-summary
        filter_group("fg-s1-city", "s1-fc-city", "health-summary", "city", "sheet-1"),
        # Sheet 2 — city filter on monthly-profile
        filter_group("fg-s2-city",   "s2-fc-city",   "monthly-profile", "city",   "sheet-2"),
        filter_group("fg-s2-season", "s2-fc-season", "monthly-profile", "season", "sheet-2"),
        # Sheet 3 — city + year filter on exceedance-stats
        filter_group("fg-s3-city", "s3-fc-city", "exceedance-stats", "city", "sheet-3"),
        filter_group("fg-s3-year", "s3-fc-year", "exceedance-stats", "year", "sheet-3"),
        # Sheet 4 — location + model filter on forecast-accuracy
        filter_group("fg-s4-loc",   "s4-fc-loc",   "forecast-accuracy", "location_name", "sheet-4"),
        filter_group("fg-s4-model", "s4-fc-model", "forecast-accuracy", "model",          "sheet-4"),
    ]


# ── Main definition ───────────────────────────────────────────────────────────

def build_definition() -> dict:
    return {
        "DataSetIdentifierDeclarations": [
            {"Identifier": "daily-aqi",           "DataSetArn": ds_arn("openaq-daily-aqi")},
            {"Identifier": "health-summary",       "DataSetArn": ds_arn("openaq-health-summary")},
            {"Identifier": "annual-monthly-trend", "DataSetArn": ds_arn("openaq-annual-monthly-trend")},
            {"Identifier": "monthly-profile",      "DataSetArn": ds_arn("openaq-monthly-profile")},
            {"Identifier": "diurnal-profile",      "DataSetArn": ds_arn("openaq-diurnal-profile")},
            {"Identifier": "aq-weather-daily",     "DataSetArn": ds_arn("openaq-aq-weather-daily")},
            {"Identifier": "exceedance-stats",     "DataSetArn": ds_arn("openaq-exceedance-stats")},
            {"Identifier": "pollutant-ratio",      "DataSetArn": ds_arn("openaq-pollutant-ratio")},
            {"Identifier": "forecast-accuracy",    "DataSetArn": ds_arn("openaq-forecast-accuracy")},
        ],
        "Sheets": [
            build_sheet1(),
            build_sheet2(),
            build_sheet3(),
            build_sheet4(),
        ],
        "CalculatedFields": [
            # ── aq-weather-daily ──────────────────────────────────────────────
            # Wind direction binned into 4 cardinal sectors for the sector bar chart.
            # NULL avg_wind_dir (weather fetch failed) shown as "Unknown".
            {
                "DataSetIdentifier": "aq-weather-daily",
                "Name": "wind_sector",
                "Expression": (
                    "ifelse(isNull({avg_wind_dir}), 'Unknown',"
                    " ifelse({avg_wind_dir} < 90, 'NE (0-90)',"
                    " ifelse({avg_wind_dir} < 180, 'SE (90-180)',"
                    " ifelse({avg_wind_dir} < 270, 'SW (180-270)', 'NW (270-360)'))))"
                ),
            },
            # ── exceedance-stats ──────────────────────────────────────────────
            # Days that met WHO standard (total minus any exceedance).
            {
                "DataSetIdentifier": "exceedance-stats",
                "Name": "compliant_days",
                "Expression": "{total_days} - {who_exceedance_days}",
            },
            # Days that exceeded WHO (15 µg/m³) but stayed under QCVN (50 µg/m³).
            # These are days where Vietnam is legally compliant but still unhealthy
            # by international standards.
            {
                "DataSetIdentifier": "exceedance-stats",
                "Name": "who_only_days",
                "Expression": "{who_exceedance_days} - {qcvn_exceedance_days}",
            },
        ],
        "ParameterDeclarations": [],
        "FilterGroups": build_filter_groups(),
        "Options": {
            "WeekStart": "MONDAY",
        },
    }


# ── Entry point ───────────────────────────────────────────────────────────────

PERMISSIONS = [
    {
        "Principal": USER_ARN,
        "Actions": [
            "quicksight:DescribeAnalysis",
            "quicksight:DescribeAnalysisPermissions",
            "quicksight:UpdateAnalysis",
            "quicksight:UpdateAnalysisPermissions",
            "quicksight:DeleteAnalysis",
            "quicksight:QueryAnalysis",
            "quicksight:RestoreAnalysis",
        ],
    }
]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true",
                        help="Write definition JSON but do not call AWS API")
    args = parser.parse_args()

    definition = build_definition()

    # Always write the definition JSON alongside this script (terraform/)
    def_path = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            "quicksight_analysis_definition.json")
    with open(def_path, "w", encoding="utf-8") as fh:
        json.dump(definition, fh, indent=2)
    print(f"Definition written: {def_path}")

    if args.dry_run:
        print("Dry-run mode: skipping AWS API call.")
        return

    qs = boto3.client("quicksight", region_name=REGION)

    # Prefer update_analysis over delete+create: QuickSight's CreateAnalysis
    # is unreliable when the same analysis ID was recently soft-deleted, and
    # scatter visuals / complex definitions occasionally trigger InternalFailure
    # on create but succeed on update. Update in-place preserves history and
    # avoids the delete→recreate race condition.
    print("Checking for existing analysis...")
    exists = False
    try:
        r = qs.describe_analysis(AwsAccountId=ACCOUNT_ID, AnalysisId=ANALYSIS_ID)
        status = r["Analysis"].get("Status", "")
        if status == "DELETED":
            print("Analysis is soft-deleted — restoring first...")
            qs.restore_analysis(AwsAccountId=ACCOUNT_ID, AnalysisId=ANALYSIS_ID)
            import time; time.sleep(5)
        exists = True
        print("Existing analysis found — updating in-place.")
    except ClientError as e:
        if e.response["Error"]["Code"] not in ("ResourceNotFoundException", "404"):
            raise
        print("No existing analysis — creating fresh.")

    try:
        if exists:
            resp = qs.update_analysis(
                AwsAccountId=ACCOUNT_ID,
                AnalysisId=ANALYSIS_ID,
                Name=ANALYSIS_NAME,
                Definition=definition,
            )
            print(f"  UpdateStatus : {resp.get('UpdateStatus', '?')}")
            print(f"  ARN          : {resp.get('Arn', '?')}")
        else:
            resp = qs.create_analysis(
                AwsAccountId=ACCOUNT_ID,
                AnalysisId=ANALYSIS_ID,
                Name=ANALYSIS_NAME,
                Definition=definition,
                Permissions=PERMISSIONS,
            )
            print(f"  CreationStatus : {resp.get('CreationStatus', '?')}")
            print(f"  ARN            : {resp.get('Arn', '?')}")
            print()
            print("Next steps (first-time only):")
            print(f"  terraform import aws_quicksight_analysis.openaq \\")
            print(f"    {ACCOUNT_ID}/{ANALYSIS_ID}")
        print()
        print("Analysis updated successfully.")
    except ClientError as e:
        print(f"API error: {e}", file=sys.stderr)
        try:
            import time; time.sleep(3)
            detail = qs.describe_analysis(
                AwsAccountId=ACCOUNT_ID, AnalysisId=ANALYSIS_ID
            )
            errors = detail.get("Analysis", {}).get("Errors", [])
            if errors:
                print("Analysis errors:", file=sys.stderr)
                for err in errors:
                    print(f"  {err}", file=sys.stderr)
        except Exception:
            pass
        sys.exit(1)


if __name__ == "__main__":
    main()

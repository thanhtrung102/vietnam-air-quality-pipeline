"""
forecast_generate/handler.py — PM2.5 7-day ahead forecast Lambda.

Runs two model families per station and writes Parquet to S3:

  1. SARIMA(1,1,1)(1,1,1,12)  — statsmodels, seasonal baseline
  2. Prophet                   — Facebook Prophet with weather regressors + VN holidays

Workflow per invocation:
  a. Fetch full PM2.5 + weather time series for all stations from
     openaq_mart.mart_lagged_features via Athena.
  b. Per station:
       i.  30-day holdout split → fit both models → compute holdout RMSE
       ii. Refit on full series → generate 7-day forecast
       iii Emit CloudWatch ForecastRMSE metric per model / city
  c. Write Parquet to
     processed/openaq_mart/mart_daily_forecast/generated_at={date}/model={model}/
  d. Publish SNS alert if any forecast day > AQI 150 (Unhealthy threshold).

Container image: see Dockerfile. Deploy via ECR.
Scheduled daily at 03:00 UTC by EventBridge Scheduler (after weather_ingest + dbt).

Environment variables:
  S3_BUCKET_NAME       — project S3 bucket
  ATHENA_DATABASE      — Glue database (default: openaq_mart)
  ATHENA_WORKGROUP     — Athena workgroup (default: openaq_workgroup)
  SNS_ALERT_TOPIC_ARN  — SNS topic for AQI > 150 alerts
  FORECAST_HORIZON     — days ahead (default: 7)
  HOLDOUT_DAYS         — holdout window for A/B (default: 30)
  MIN_TRAIN_DAYS       — minimum rows required to fit (default: 60)
"""

import io
import json
import logging
import math
import os
import time
import warnings
from datetime import date, timedelta

import boto3
import numpy as np
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq

warnings.filterwarnings("ignore")

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

S3_BUCKET       = os.environ["S3_BUCKET_NAME"]
ATHENA_DATABASE = os.environ.get("ATHENA_DATABASE", "openaq_mart")
ATHENA_WORKGROUP = os.environ.get("ATHENA_WORKGROUP", "openaq_workgroup")
SNS_TOPIC_ARN   = os.environ.get("SNS_ALERT_TOPIC_ARN", "")
FORECAST_HORIZON = int(os.environ.get("FORECAST_HORIZON", "7"))
HOLDOUT_DAYS    = int(os.environ.get("HOLDOUT_DAYS", "30"))
MIN_TRAIN_DAYS  = int(os.environ.get("MIN_TRAIN_DAYS", "60"))

# AQI 150 = Unhealthy threshold (PM2.5 > 55.4 µg/m³)
AQI_ALERT_THRESHOLD = 150

# VN public holidays for Prophet (date, name pairs)
VN_HOLIDAYS_PROPHET = pd.DataFrame({
    "holiday": [
        "New Year", "New Year",
        "Tet", "Tet", "Tet", "Tet", "Tet", "Tet", "Tet",
        "Hung Kings",
        "Liberation Day", "Labour Day",
        "National Day",
        "Tet", "Tet", "Tet", "Tet", "Tet", "Tet", "Tet",
        "Hung Kings",
        "Liberation Day", "Labour Day",
        "National Day",
        "Tet", "Tet", "Tet", "Tet", "Tet", "Tet", "Tet",
        "Hung Kings",
        "Liberation Day", "Labour Day",
        "National Day",
        "New Year",
        "Tet", "Tet", "Tet", "Tet", "Tet", "Tet", "Tet",
        "Hung Kings",
        "Liberation Day", "Labour Day",
        "National Day",
    ],
    "ds": pd.to_datetime([
        "2023-01-01", "2024-01-01",
        "2023-01-20", "2023-01-21", "2023-01-22", "2023-01-23",
        "2023-01-24", "2023-01-25", "2023-01-26",
        "2023-04-29",
        "2023-04-30", "2023-05-01",
        "2023-09-02",
        "2024-02-08", "2024-02-09", "2024-02-10", "2024-02-11",
        "2024-02-12", "2024-02-13", "2024-02-14",
        "2024-04-18",
        "2024-04-30", "2024-05-01",
        "2024-09-02",
        "2025-01-27", "2025-01-28", "2025-01-29", "2025-01-30",
        "2025-01-31", "2025-02-01", "2025-02-02",
        "2025-04-07",
        "2025-04-30", "2025-05-01",
        "2025-09-02",
        "2026-01-01",
        "2026-02-14", "2026-02-15", "2026-02-16", "2026-02-17",
        "2026-02-18", "2026-02-19", "2026-02-20",
        "2026-03-28",
        "2026-04-30", "2026-05-01",
        "2026-09-02",
    ]),
    "lower_window": 0,
    "upper_window": 1,
})

# ── US EPA PM2.5 AQI breakpoints (2024 update) ───────────────────────────────

_AQI_BP = [
    (0.0,   9.0,   0,  50),
    (9.1,  35.4,  51, 100),
    (35.5, 55.4, 101, 150),
    (55.5, 125.4, 151, 200),
    (125.5, 225.4, 201, 300),
    (225.5, 325.4, 301, 500),
]

def _pm25_to_aqi(pm25: float) -> int:
    if pm25 is None or math.isnan(pm25) or pm25 < 0:
        return 0
    for lo_c, hi_c, lo_a, hi_a in _AQI_BP:
        if lo_c <= pm25 <= hi_c:
            return int(round(lo_a + (pm25 - lo_c) / (hi_c - lo_c) * (hi_a - lo_a)))
    return 500

def _aqi_category(aqi: int) -> str:
    if aqi <= 50:  return "Good"
    if aqi <= 100: return "Moderate"
    if aqi <= 150: return "Unhealthy for Sensitive Groups"
    if aqi <= 200: return "Unhealthy"
    if aqi <= 300: return "Very Unhealthy"
    return "Hazardous"


# ── Athena helpers ────────────────────────────────────────────────────────────

def _run_athena(sql: str) -> list[dict]:
    client = boto3.client("athena")
    resp = client.start_query_execution(
        QueryString=sql,
        QueryExecutionContext={"Database": ATHENA_DATABASE},
        ResultConfiguration={
            "OutputLocation": f"s3://{S3_BUCKET}/athena-results/"
        },
        WorkGroup=ATHENA_WORKGROUP,
    )
    qid = resp["QueryExecutionId"]
    for _ in range(150):   # up to 5 minutes
        execution = client.get_query_execution(QueryExecutionId=qid)["QueryExecution"]
        state = execution["Status"]["State"]
        if state == "SUCCEEDED":
            break
        if state in ("FAILED", "CANCELLED"):
            reason = execution["Status"].get("StateChangeReason", "unknown")
            raise RuntimeError(f"Athena {state}: {reason}")
        time.sleep(2)
    else:
        raise TimeoutError("Athena query timed out after 5 minutes")

    paginator = client.get_paginator("get_query_results")
    rows, headers = [], None
    for page in paginator.paginate(QueryExecutionId=qid):
        for row in page["ResultSet"]["Rows"]:
            values = [d.get("VarCharValue", "") for d in row["Data"]]
            if headers is None:
                headers = values
            else:
                rows.append(dict(zip(headers, values)))
    return rows


def _fetch_all_series() -> pd.DataFrame:
    """Return full mart_lagged_features time series for all stations."""
    sql = """
        SELECT
            location_id,
            location_name,
            city,
            CAST(measurement_date AS VARCHAR) AS measurement_date,
            avg_pm25,
            COALESCE(avg_rh_2m,              65.0) AS avg_rh_2m,
            COALESCE(avg_wind_speed,          2.0)  AS avg_wind_speed,
            COALESCE(total_precipitation_mm,  0.0)  AS total_precipitation_mm,
            COALESCE(CAST(inversion_risk AS DOUBLE), 0.0) AS inversion_risk
        FROM openaq_mart.mart_lagged_features
        WHERE avg_pm25 IS NOT NULL
        ORDER BY location_id, measurement_date
    """
    rows = _run_athena(sql)
    if not rows:
        return pd.DataFrame()
    df = pd.DataFrame(rows)
    df["measurement_date"] = pd.to_datetime(df["measurement_date"])
    for col in ["avg_pm25", "avg_rh_2m", "avg_wind_speed",
                "total_precipitation_mm", "inversion_risk"]:
        df[col] = pd.to_numeric(df[col], errors="coerce").fillna(0)
    df["location_id"] = pd.to_numeric(df["location_id"]).astype(int)
    return df


# ── SARIMA model ──────────────────────────────────────────────────────────────

def _fit_sarima(train_pm25: pd.Series, n_seasonal_years: int = 0):
    """Fit SARIMA. Uses seasonal order only when >= 2 years of data."""
    from statsmodels.tsa.statespace.sarimax import SARIMAX

    if n_seasonal_years >= 2 and len(train_pm25) >= 730:
        seasonal_order = (1, 1, 1, 365)   # annual daily seasonality
    elif n_seasonal_years >= 1 and len(train_pm25) >= 365:
        seasonal_order = (1, 0, 1, 365)
    else:
        seasonal_order = (0, 0, 0, 0)     # plain ARIMA for short series

    model = SARIMAX(
        train_pm25,
        order=(1, 1, 1),
        seasonal_order=seasonal_order,
        enforce_stationarity=False,
        enforce_invertibility=False,
        trend="n",
    )
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        result = model.fit(disp=False, maxiter=200)
    return result


def _forecast_sarima(result, horizon: int = 7) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    forecast = result.get_forecast(steps=horizon)
    mean = np.maximum(0, forecast.predicted_mean.values)
    ci   = forecast.conf_int(alpha=0.05)
    lo   = np.maximum(0, ci.iloc[:, 0].values)
    hi   = np.maximum(0, ci.iloc[:, 1].values)
    return mean, lo, hi


# ── Prophet model ─────────────────────────────────────────────────────────────

def _fit_prophet(train_df: pd.DataFrame):
    """Fit Prophet with weather regressors and VN holidays."""
    from prophet import Prophet

    m = Prophet(
        yearly_seasonality=True,
        weekly_seasonality=True,
        daily_seasonality=False,
        seasonality_mode="multiplicative",
        holidays=VN_HOLIDAYS_PROPHET,
        interval_width=0.95,
    )
    m.add_regressor("avg_rh_2m")
    m.add_regressor("avg_wind_speed")
    m.add_regressor("total_precipitation_mm")
    m.add_regressor("inversion_risk")

    prophet_df = train_df.rename(columns={
        "measurement_date": "ds",
        "avg_pm25":         "y",
    })[["ds", "y", "avg_rh_2m", "avg_wind_speed",
        "total_precipitation_mm", "inversion_risk"]]

    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        m.fit(prophet_df)
    return m


def _forecast_prophet(
    model, last_date: pd.Timestamp, train_df: pd.DataFrame, horizon: int = 7
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Generate Prophet forecast; fill future regressors with 7-day trailing mean."""
    future_dates = [last_date + timedelta(days=i + 1) for i in range(horizon)]
    reg_cols = ["avg_rh_2m", "avg_wind_speed", "total_precipitation_mm", "inversion_risk"]

    # Use last 7-day mean as regressor fallback for future dates (no weather forecast)
    reg_means = train_df[reg_cols].tail(7).mean()

    future_rows = [{
        "ds": pd.Timestamp(d),
        **{c: reg_means[c] for c in reg_cols}
    } for d in future_dates]

    future_df = pd.concat(
        [model.history[["ds"] + reg_cols].assign(**{}), pd.DataFrame(future_rows)],
        ignore_index=True,
    )
    # Ensure regressor columns are present throughout
    for c in reg_cols:
        future_df[c] = future_df[c].fillna(reg_means[c])

    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        fcst = model.predict(future_df)

    tail = fcst.tail(horizon)
    mean = np.maximum(0, tail["yhat"].values)
    lo   = np.maximum(0, tail["yhat_lower"].values)
    hi   = np.maximum(0, tail["yhat_upper"].values)
    return mean, lo, hi


# ── Holdout evaluation ────────────────────────────────────────────────────────

def _holdout_rmse(predicted: np.ndarray, actual: np.ndarray) -> float:
    return float(np.sqrt(np.mean((predicted - actual) ** 2)))


# ── CloudWatch metric emission ────────────────────────────────────────────────

def _emit_rmse_metric(cw_client, model: str, city: str, rmse: float) -> None:
    try:
        cw_client.put_metric_data(
            Namespace="OpenAQ/Pipeline",
            MetricData=[{
                "MetricName": "ForecastRMSE",
                "Dimensions": [
                    {"Name": "Model", "Value": model},
                    {"Name": "City",  "Value": city},
                ],
                "Value":           rmse,
                "Unit":            "None",
            }],
        )
    except Exception as exc:
        logger.warning("CloudWatch metric emit failed: %s", exc)


# ── Parquet output schema ─────────────────────────────────────────────────────

_FORECAST_SCHEMA = pa.schema([
    pa.field("location_id",          pa.int32()),
    pa.field("location_name",        pa.string()),
    pa.field("city",                 pa.string()),
    pa.field("forecast_date",        pa.date32()),
    pa.field("forecast_pm25",        pa.float64()),
    pa.field("forecast_aqi",         pa.int32()),
    pa.field("forecast_aqi_category",pa.string()),
    pa.field("ci_lower_95",          pa.float64()),
    pa.field("ci_upper_95",          pa.float64()),
    pa.field("holdout_rmse",         pa.float64()),
])

def _write_parquet(records: list[dict], s3_client, generated_at: str, model: str) -> None:
    if not records:
        return
    table = pa.table(
        {f.name: [r[f.name] for r in records] for f in _FORECAST_SCHEMA},
        schema=_FORECAST_SCHEMA,
    )
    key = (
        f"processed/openaq_mart/mart_daily_forecast/"
        f"generated_at={generated_at}/model={model}/part-0.parquet"
    )
    buf = io.BytesIO()
    pq.write_table(table, buf, compression="snappy")
    s3_client.put_object(Bucket=S3_BUCKET, Key=key, Body=buf.getvalue())
    logger.info("Wrote %d rows to s3://%s/%s", len(records), S3_BUCKET, key)


# ── Main handler ──────────────────────────────────────────────────────────────

def handler(event, context):
    generated_at = date.today().isoformat()
    s3  = boto3.client("s3")
    sns = boto3.client("sns") if SNS_TOPIC_ARN else None
    cw  = boto3.client("cloudwatch")

    logger.info("Fetching mart_lagged_features from Athena …")
    all_data = _fetch_all_series()
    if all_data.empty:
        logger.error("No data returned from mart_lagged_features — aborting")
        return {"status": "no_data"}

    station_ids = all_data["location_id"].unique()
    logger.info("Processing %d stations", len(station_ids))

    sarima_records:  list[dict] = []
    prophet_records: list[dict] = []
    alert_messages:  list[str]  = []
    errors = 0

    # Per-city RMSE accumulator for CloudWatch (one metric per city × model)
    city_rmse: dict[tuple, list] = {}

    for loc_id in station_ids:
        sdf = all_data[all_data["location_id"] == loc_id].sort_values("measurement_date").copy()
        if len(sdf) < MIN_TRAIN_DAYS:
            logger.warning("Station %s: only %d rows — skipping", loc_id, len(sdf))
            continue

        loc_name = sdf["location_name"].iloc[0]
        city     = sdf["city"].iloc[0]
        pm25_ser = sdf.set_index("measurement_date")["avg_pm25"]
        n_years  = len(sdf) // 365

        try:
            # ── Holdout A/B split ──────────────────────────────────────────
            train_df   = sdf.iloc[:-HOLDOUT_DAYS]
            holdout_df = sdf.iloc[-HOLDOUT_DAYS:]
            train_pm25 = train_df.set_index("measurement_date")["avg_pm25"]
            actual_ho  = holdout_df["avg_pm25"].values

            # ── SARIMA holdout ─────────────────────────────────────────────
            sarima_result_ho = _fit_sarima(train_pm25, n_years)
            sarima_ho_pred, _, _ = _forecast_sarima(sarima_result_ho, HOLDOUT_DAYS)
            sarima_rmse = _holdout_rmse(sarima_ho_pred, actual_ho)

            # ── Prophet holdout ────────────────────────────────────────────
            prophet_model_ho = _fit_prophet(train_df)
            prophet_ho_pred, _, _ = _forecast_prophet(
                prophet_model_ho, train_df["measurement_date"].iloc[-1], train_df, HOLDOUT_DAYS
            )
            prophet_rmse = _holdout_rmse(prophet_ho_pred, actual_ho)

            logger.info(
                "Station %s (%s): SARIMA RMSE=%.2f, Prophet RMSE=%.2f",
                loc_id, city, sarima_rmse, prophet_rmse,
            )

            # Accumulate for city-level CloudWatch metric
            for model_key, rmse in [("sarima", sarima_rmse), ("prophet", prophet_rmse)]:
                key = (model_key, city)
                city_rmse.setdefault(key, []).append(rmse)

            # ── Full-series refit + 7-day forecast ─────────────────────────
            sarima_full   = _fit_sarima(pm25_ser, n_years)
            s_mean, s_lo, s_hi = _forecast_sarima(sarima_full, FORECAST_HORIZON)

            prophet_full  = _fit_prophet(sdf)
            last_date     = sdf["measurement_date"].iloc[-1]
            p_mean, p_lo, p_hi = _forecast_prophet(prophet_full, last_date, sdf, FORECAST_HORIZON)

            # ── Build records ──────────────────────────────────────────────
            for h in range(FORECAST_HORIZON):
                fdate = (last_date + timedelta(days=h + 1)).date()
                base  = {
                    "location_id":   loc_id,
                    "location_name": loc_name,
                    "city":          city,
                    "forecast_date": fdate,
                }

                s_aqi = _pm25_to_aqi(s_mean[h])
                sarima_records.append({
                    **base,
                    "forecast_pm25":         round(float(s_mean[h]), 4),
                    "forecast_aqi":          s_aqi,
                    "forecast_aqi_category": _aqi_category(s_aqi),
                    "ci_lower_95":           round(float(s_lo[h]), 4),
                    "ci_upper_95":           round(float(s_hi[h]), 4),
                    "holdout_rmse":          round(sarima_rmse, 4),
                })
                if s_aqi > AQI_ALERT_THRESHOLD:
                    alert_messages.append(
                        f"{city} / {loc_name}: SARIMA forecast {fdate} AQI={s_aqi} "
                        f"(PM2.5 {s_mean[h]:.1f} µg/m³)"
                    )

                p_aqi = _pm25_to_aqi(p_mean[h])
                prophet_records.append({
                    **base,
                    "forecast_pm25":         round(float(p_mean[h]), 4),
                    "forecast_aqi":          p_aqi,
                    "forecast_aqi_category": _aqi_category(p_aqi),
                    "ci_lower_95":           round(float(p_lo[h]), 4),
                    "ci_upper_95":           round(float(p_hi[h]), 4),
                    "holdout_rmse":          round(prophet_rmse, 4),
                })
                if p_aqi > AQI_ALERT_THRESHOLD:
                    alert_messages.append(
                        f"{city} / {loc_name}: Prophet forecast {fdate} AQI={p_aqi} "
                        f"(PM2.5 {p_mean[h]:.1f} µg/m³)"
                    )

        except Exception as exc:
            logger.error("Station %s failed: %s", loc_id, exc, exc_info=True)
            errors += 1

    # ── Emit city-level RMSE metrics to CloudWatch ────────────────────────
    for (model_key, city), rmse_list in city_rmse.items():
        mean_rmse = float(np.mean(rmse_list))
        _emit_rmse_metric(cw, model_key, city, mean_rmse)

    # ── Write Parquet ─────────────────────────────────────────────────────
    _write_parquet(sarima_records,  s3, generated_at, "sarima")
    _write_parquet(prophet_records, s3, generated_at, "prophet")

    # ── SNS alerts ────────────────────────────────────────────────────────
    if alert_messages and sns and SNS_TOPIC_ARN:
        body = (
            f"⚠️ Vietnam AQI FORECAST ALERT ({generated_at})\n\n"
            + "\n".join(alert_messages)
            + f"\n\nForecast horizon: {FORECAST_HORIZON} days\n"
            f"Stations processed: {len(station_ids)}\n"
            f"Errors: {errors}"
        )
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=f"Vietnam AQI Forecast Alert — {len(alert_messages)} high-risk day(s)",
            Message=body,
        )
        logger.info("SNS alert sent: %d high-risk forecast days", len(alert_messages))

    result = {
        "generated_at":    generated_at,
        "stations_ok":     len(station_ids) - errors,
        "errors":          errors,
        "sarima_records":  len(sarima_records),
        "prophet_records": len(prophet_records),
        "alert_count":     len(alert_messages),
    }
    logger.info("Completed: %s", json.dumps(result))
    return result

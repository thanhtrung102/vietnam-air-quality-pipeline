"""
forecast_generate/handler.py — PM2.5 7-day ahead forecast Lambda.

Runs SARIMA per station and writes Parquet to S3:

  SARIMA(1,1,1)(1,0,1,7) — statsmodels, weekly-seasonal baseline

Workflow per invocation:
  a. Fetch full PM2.5 time series for all stations from
     openaq_mart.mart_lagged_features via Athena.
  b. Per station:
       i.  30-day holdout split → fit SARIMA → compute holdout RMSE
       ii. Refit on full series → generate 7-day forecast
       iii Emit CloudWatch ForecastRMSE metric per city
  c. Write Parquet to
     processed/openaq_mart/mart_daily_forecast/generated_at={date}/model=sarima/
  d. Publish SNS alert if any forecast day > AQI 150 (Unhealthy threshold).

Container image: see Dockerfile. Deploy via ECR.
Scheduled daily at 03:00 UTC by EventBridge Scheduler (after weather_ingest + dbt).

Note on model choice: Prophet was removed due to prophet/cmdstanpy/cmdstan
version incompatibility inside the Lambda container image. SARIMA(1,1,1)(1,0,1,7)
captures the dominant weekly PM2.5 cycle (weekday/weekend effect) and produces
reliable 7-day forecasts. Annual seasonality is encoded via month_sin/month_cos
features available in mart_lagged_features (not used here, but available for
future ML model extensions).

Environment variables:
  S3_BUCKET_NAME       — project S3 bucket
  ATHENA_DATABASE      — Glue database (default: openaq_mart)
  ATHENA_WORKGROUP     — Athena workgroup (default: openaq_workgroup)
  SNS_ALERT_TOPIC_ARN  — SNS topic for AQI > 150 alerts
  FORECAST_HORIZON     — days ahead (default: 7)
  HOLDOUT_DAYS         — holdout window for A/B (default: 30)
  MIN_TRAIN_DAYS       — minimum rows required to fit (default: 60)
"""

import gc
import io
import json
import logging
import math
import os
import sys
import warnings
from datetime import date, timedelta

import boto3
import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "shared"))
from athena_utils import AthenaConfig, run_query  # noqa: E402
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq

warnings.filterwarnings("ignore")

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

S3_BUCKET        = os.environ["S3_BUCKET_NAME"]
ATHENA_DATABASE  = os.environ.get("ATHENA_DATABASE", "openaq_mart")
ATHENA_WORKGROUP = os.environ.get("ATHENA_WORKGROUP", "openaq_workgroup")
SNS_TOPIC_ARN    = os.environ.get("SNS_ALERT_TOPIC_ARN", "")
FORECAST_HORIZON  = int(os.environ.get("FORECAST_HORIZON", "7"))
HOLDOUT_DAYS      = int(os.environ.get("HOLDOUT_DAYS", "30"))
MIN_TRAIN_DAYS    = int(os.environ.get("MIN_TRAIN_DAYS", "60"))
# Skip stations whose latest data is older than this many days.
# Guards against alerting on forecasts rooted in stale historical data.
MAX_STALENESS_DAYS = int(os.environ.get("MAX_STALENESS_DAYS", "90"))

AQI_ALERT_THRESHOLD = 150

# ── US EPA PM2.5 AQI breakpoints (2024 update) ───────────────────────────────

_AQI_BP = [
    (0.0,    9.0,   0,  50),
    (9.1,   35.4,  51, 100),
    (35.5,  55.4, 101, 150),
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

_ATHENA_CFG = AthenaConfig(
    database=ATHENA_DATABASE,
    workgroup=ATHENA_WORKGROUP,
    output_location=f"s3://{S3_BUCKET}/athena-results/",
)


def _fetch_all_series() -> pd.DataFrame:
    """Return full PM2.5 time series for all stations from mart_lagged_features."""
    sql = """
        SELECT
            location_id,
            location_name,
            city,
            CAST(measurement_date AS VARCHAR) AS measurement_date,
            avg_pm25
        FROM openaq_mart.mart_lagged_features
        WHERE avg_pm25 IS NOT NULL
        ORDER BY location_id, measurement_date
    """
    client = boto3.client("athena")
    rows = run_query(client, sql, _ATHENA_CFG, max_wait=300)
    if not rows:
        return pd.DataFrame()
    df = pd.DataFrame(rows)
    df["measurement_date"] = pd.to_datetime(df["measurement_date"])
    df["avg_pm25"] = pd.to_numeric(df["avg_pm25"], errors="coerce").fillna(0)
    df["location_id"] = pd.to_numeric(df["location_id"]).astype(int)
    return df


# ── SARIMA model ──────────────────────────────────────────────────────────────

def _fit_sarima(train_pm25: pd.Series):
    """Fit SARIMA(1,1,1)(1,0,1,7) — weekly seasonality.

    Period=7 captures the dominant weekday/weekend PM2.5 cycle efficiently.
    Annual seasonality (period=365) was dropped: it requires a Kalman filter
    state of 365+ dimensions and exhausts Lambda memory at 3008 MB across
    15 simultaneous station fits.
    """
    from statsmodels.tsa.statespace.sarimax import SARIMAX

    seasonal_order = (1, 0, 1, 7) if len(train_pm25) >= 14 else (0, 0, 0, 0)
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


# ── Holdout evaluation ────────────────────────────────────────────────────────

def _holdout_rmse(predicted: np.ndarray, actual: np.ndarray) -> float:
    return float(np.sqrt(np.mean((predicted - actual) ** 2)))


# ── CloudWatch metric emission ────────────────────────────────────────────────

def _emit_rmse_metric(cw_client, city: str, rmse: float) -> None:
    try:
        cw_client.put_metric_data(
            Namespace="OpenAQ/Pipeline",
            MetricData=[{
                "MetricName": "ForecastRMSE",
                "Dimensions": [
                    {"Name": "Model", "Value": "sarima"},
                    {"Name": "City",  "Value": city},
                ],
                "Value": rmse,
                "Unit":  "None",
            }],
        )
    except Exception as exc:
        logger.warning("CloudWatch metric emit failed: %s", exc)


# ── Parquet output schema ─────────────────────────────────────────────────────

_FORECAST_SCHEMA = pa.schema([
    pa.field("location_id",           pa.int32()),
    pa.field("location_name",         pa.string()),
    pa.field("city",                  pa.string()),
    pa.field("forecast_date",         pa.date32()),
    pa.field("forecast_pm25",         pa.float64()),
    pa.field("forecast_aqi",          pa.int32()),
    pa.field("forecast_aqi_category", pa.string()),
    pa.field("ci_lower_95",           pa.float64()),
    pa.field("ci_upper_95",           pa.float64()),
    pa.field("holdout_rmse",          pa.float64()),
])

def _write_parquet(records: list[dict], s3_client, generated_at: str) -> None:
    if not records:
        return
    table = pa.table(
        {f.name: [r[f.name] for r in records] for f in _FORECAST_SCHEMA},
        schema=_FORECAST_SCHEMA,
    )
    key = (
        f"processed/openaq_mart/mart_daily_forecast/"
        f"generated_at={generated_at}/model=sarima/part-0.parquet"
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

    sarima_records: list[dict] = []
    alert_messages: list[str]  = []
    city_rmse: dict[str, list] = {}
    errors = 0

    for loc_id in station_ids:
        sdf = all_data[all_data["location_id"] == loc_id].sort_values("measurement_date").copy()
        if len(sdf) < MIN_TRAIN_DAYS:
            logger.warning("Station %s: only %d rows — skipping", loc_id, len(sdf))
            continue

        loc_name  = sdf["location_name"].iloc[0]
        city      = sdf["city"].iloc[0]
        last_date = sdf["measurement_date"].iloc[-1]
        staleness = (date.today() - last_date.date()).days
        if staleness > MAX_STALENESS_DAYS:
            logger.warning(
                "Station %s (%s): latest data is %d days old — skipping (MAX_STALENESS_DAYS=%d)",
                loc_id, loc_name, staleness, MAX_STALENESS_DAYS,
            )
            continue

        pm25_ser = sdf.set_index("measurement_date")["avg_pm25"]

        sarima_result_ho = sarima_full = None
        try:
            # ── Holdout A/B split ──────────────────────────────────────────
            train_pm25 = pm25_ser.iloc[:-HOLDOUT_DAYS]
            actual_ho  = pm25_ser.iloc[-HOLDOUT_DAYS:].values

            # ── SARIMA holdout ─────────────────────────────────────────────
            sarima_result_ho = _fit_sarima(train_pm25)
            sarima_ho_pred, _, _ = _forecast_sarima(sarima_result_ho, HOLDOUT_DAYS)
            sarima_rmse = _holdout_rmse(sarima_ho_pred, actual_ho)

            logger.info("Station %s (%s): SARIMA RMSE=%.2f", loc_id, city, sarima_rmse)
            city_rmse.setdefault(city, []).append(sarima_rmse)

            # ── Full-series refit + 7-day forecast ─────────────────────────
            sarima_full = _fit_sarima(pm25_ser)
            s_mean, s_lo, s_hi = _forecast_sarima(sarima_full, FORECAST_HORIZON)

            for h in range(FORECAST_HORIZON):
                fdate = (last_date + timedelta(days=h + 1)).date()
                s_aqi = _pm25_to_aqi(s_mean[h])
                sarima_records.append({
                    "location_id":           loc_id,
                    "location_name":         loc_name,
                    "city":                  city,
                    "forecast_date":         fdate,
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

        except Exception as exc:
            logger.error("Station %s failed: %s", loc_id, exc, exc_info=True)
            errors += 1
        finally:
            sarima_result_ho = sarima_full = None
            gc.collect()

    # ── Emit city-level RMSE metrics to CloudWatch ────────────────────────
    for city, rmse_list in city_rmse.items():
        _emit_rmse_metric(cw, city, float(np.mean(rmse_list)))

    # ── Write Parquet ─────────────────────────────────────────────────────
    _write_parquet(sarima_records, s3, generated_at)

    # ── SNS alerts ────────────────────────────────────────────────────────
    if alert_messages and sns and SNS_TOPIC_ARN:
        body = (
            f"Vietnam AQI FORECAST ALERT ({generated_at})\n\n"
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
        "generated_at":   generated_at,
        "stations_ok":    len(station_ids) - errors,
        "errors":         errors,
        "sarima_records": len(sarima_records),
        "alert_count":    len(alert_messages),
    }
    logger.info("Completed: %s", json.dumps(result))
    return result

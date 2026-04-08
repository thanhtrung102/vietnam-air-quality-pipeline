"""
Tests for lambda/forecast_generate/handler.py

Heavy dependencies (numpy, pandas, pyarrow, statsmodels) are not available in
the local test environment. They are stubbed via sys.modules before the handler
module is imported. Tests focus on:

  - _pm25_to_aqi:   AQI calculation at each EPA breakpoint boundary
  - _aqi_category:  health category label at each AQI boundary
  - _emit_rmse_metric: CloudWatch put_metric_data dimensions and namespace
  - _write_parquet:    S3 put_object called with correct key path
  - handler:           no-data early-exit path
  - handler:           SNS alert published when forecast AQI > AQI_ALERT_THRESHOLD
  - handler:           SNS not published when all forecasts are below threshold
"""

import math
import os
import sys
from unittest.mock import MagicMock, patch, call, ANY
import pytest

# ── Stub heavy dependencies before importing the handler ──────────────────────
# Each stub is inserted only if not already present so that a real installation
# (e.g. in the Lambda container CI) takes precedence.

_STUBS = [
    "numpy", "pandas",
    "pyarrow", "pyarrow.parquet",
    "statsmodels",
    "statsmodels.tsa",
    "statsmodels.tsa.statespace",
    "statsmodels.tsa.statespace.sarimax",
]
for _mod in _STUBS:
    sys.modules.setdefault(_mod, MagicMock())

# Give numpy enough real behaviour for _pm25_to_aqi and _holdout_rmse.
# math.isnan / math.sqrt are stdlib — no numpy needed there.
np_stub = sys.modules["numpy"]
np_stub.sqrt  = math.sqrt
np_stub.isnan = math.isnan
np_stub.bool_ = bool   # pytest.approx uses isinstance(val, np.bool_) internally

# ── Environment variables consumed at module import time ──────────────────────
os.environ["S3_BUCKET_NAME"]      = "test-bucket"
os.environ["ATHENA_DATABASE"]     = "openaq_mart"
os.environ["ATHENA_WORKGROUP"]    = "openaq_workgroup"
os.environ["SNS_ALERT_TOPIC_ARN"] = "arn:aws:sns:ap-southeast-1:123456789012:openaq_alerts"
os.environ["FORECAST_HORIZON"]    = "7"
os.environ["HOLDOUT_DAYS"]        = "30"
os.environ["MIN_TRAIN_DAYS"]      = "60"

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "forecast_generate"))
sys.modules.pop("handler", None)  # avoid caching collision when running full suite
import handler as h  # noqa: E402


# ── _pm25_to_aqi ──────────────────────────────────────────────────────────────

class TestPm25ToAqi:
    def test_negative_returns_zero(self):
        assert h._pm25_to_aqi(-1.0) == 0

    def test_none_returns_zero(self):
        assert h._pm25_to_aqi(None) == 0

    def test_good_lower_bound(self):
        # PM2.5 = 0.0 → AQI breakpoint (0.0, 9.0, 0, 50): AQI = 0
        assert h._pm25_to_aqi(0.0) == 0

    def test_good_upper_bound(self):
        # PM2.5 = 9.0 → top of Good range → AQI = 50
        assert h._pm25_to_aqi(9.0) == 50

    def test_moderate(self):
        # PM2.5 = 9.1 → bottom of Moderate range → AQI = 51
        assert h._pm25_to_aqi(9.1) == 51

    def test_moderate_midpoint(self):
        # PM2.5 = 22.25 ≈ midpoint of (9.1, 35.4) → AQI ≈ 75
        aqi = h._pm25_to_aqi(22.25)
        assert 70 <= aqi <= 80

    def test_unhealthy_sensitive_groups(self):
        # PM2.5 = 35.5 → bottom of USG range → AQI = 101
        assert h._pm25_to_aqi(35.5) == 101

    def test_unhealthy(self):
        # PM2.5 = 55.5 → bottom of Unhealthy range → AQI = 151
        assert h._pm25_to_aqi(55.5) == 151

    def test_very_unhealthy(self):
        # PM2.5 = 125.5 → bottom of Very Unhealthy range → AQI = 201
        assert h._pm25_to_aqi(125.5) == 201

    def test_hazardous(self):
        # PM2.5 = 225.5 → bottom of Hazardous range → AQI = 301
        assert h._pm25_to_aqi(225.5) == 301

    def test_above_max_returns_500(self):
        # PM2.5 > 325.4 is above all breakpoints → 500
        assert h._pm25_to_aqi(500.0) == 500


# ── _aqi_category ─────────────────────────────────────────────────────────────

class TestAqiCategory:
    def test_good(self):
        assert h._aqi_category(0)  == "Good"
        assert h._aqi_category(50) == "Good"

    def test_moderate(self):
        assert h._aqi_category(51)  == "Moderate"
        assert h._aqi_category(100) == "Moderate"

    def test_unhealthy_sensitive(self):
        assert h._aqi_category(101) == "Unhealthy for Sensitive Groups"
        assert h._aqi_category(150) == "Unhealthy for Sensitive Groups"

    def test_unhealthy(self):
        assert h._aqi_category(151) == "Unhealthy"
        assert h._aqi_category(200) == "Unhealthy"

    def test_very_unhealthy(self):
        assert h._aqi_category(201) == "Very Unhealthy"
        assert h._aqi_category(300) == "Very Unhealthy"

    def test_hazardous(self):
        assert h._aqi_category(301) == "Hazardous"
        assert h._aqi_category(500) == "Hazardous"


# ── _emit_rmse_metric ─────────────────────────────────────────────────────────

def test_emit_rmse_metric_correct_dimensions():
    """put_metric_data called with ForecastRMSE, correct Model/City dimensions."""
    cw = MagicMock()
    h._emit_rmse_metric(cw, "Hanoi", 18.4)

    cw.put_metric_data.assert_called_once()
    kwargs = cw.put_metric_data.call_args[1]
    assert kwargs["Namespace"] == "OpenAQ/Pipeline"

    metric = kwargs["MetricData"][0]
    assert metric["MetricName"] == "ForecastRMSE"
    assert metric["Value"]      == 18.4

    dims = {d["Name"]: d["Value"] for d in metric["Dimensions"]}
    assert dims["Model"] == "sarima"
    assert dims["City"]  == "Hanoi"


def test_emit_rmse_metric_swallows_cloudwatch_error():
    """_emit_rmse_metric does not raise if CloudWatch call fails."""
    cw = MagicMock()
    cw.put_metric_data.side_effect = Exception("CW unavailable")
    h._emit_rmse_metric(cw, "HCMC", 30.0)  # must not raise


# ── _write_parquet ────────────────────────────────────────────────────────────

def test_write_parquet_s3_key_format():
    """_write_parquet writes to the correct S3 key under processed/openaq_mart/."""
    s3 = MagicMock()
    records = [{
        "location_id":           7441,
        "location_name":         "Hanoi US Embassy",
        "city":                  "Hanoi",
        "forecast_date":         MagicMock(),  # date obj — pyarrow is stubbed
        "forecast_pm25":         20.5,
        "forecast_aqi":          72,
        "forecast_aqi_category": "Moderate",
        "ci_lower_95":           15.0,
        "ci_upper_95":           26.0,
        "holdout_rmse":          8.3,
    }]

    h._write_parquet(records, s3, "2026-03-26")

    s3.put_object.assert_called_once()
    key = s3.put_object.call_args[1]["Key"]
    assert key.startswith("processed/openaq_mart/mart_daily_forecast/")
    assert "generated_at=2026-03-26" in key
    assert "model=sarima" in key
    assert key.endswith(".parquet")


def test_write_parquet_empty_records_skipped():
    """_write_parquet does not call s3 when records list is empty."""
    s3 = MagicMock()
    h._write_parquet([], s3, "2026-03-26")
    s3.put_object.assert_not_called()


# ── handler: no-data path ─────────────────────────────────────────────────────

def test_handler_no_data_returns_early():
    """handler returns {"status": "no_data"} when _fetch_all_series is empty."""
    empty_df = MagicMock()
    empty_df.empty = True

    with patch("handler._fetch_all_series", return_value=empty_df), \
         patch("handler.boto3"):
        result = h.handler({}, {})

    assert result == {"status": "no_data"}


# ── handler: SNS alert ────────────────────────────────────────────────────────

def _make_station_df(loc_id=7441, loc_name="Hanoi US Embassy",
                     city="Hanoi", n_rows=90):
    """Build a minimal mock DataFrame sufficient for one station to be processed."""
    from datetime import date as _date, timedelta

    # ── station slice returned by all_data[boolean_mask] ─────────────────────
    last_dt = MagicMock()
    last_dt.date.return_value = _date.today()
    last_dt.__add__ = MagicMock(side_effect=lambda delta: MagicMock(
        date=MagicMock(return_value=(_date.today() + delta))
    ))

    # sdf_inner is the result of sort_values("measurement_date").copy()
    sdf_inner = MagicMock()
    sdf_inner.__len__ = MagicMock(return_value=n_rows)
    sdf_inner["location_name"].iloc.__getitem__ = MagicMock(return_value=loc_name)
    sdf_inner["city"].iloc.__getitem__          = MagicMock(return_value=city)
    sdf_inner["measurement_date"].iloc.__getitem__ = MagicMock(return_value=last_dt)

    # sdf is the raw filtered slice; sort_values().copy() returns sdf_inner
    sdf = MagicMock()
    sdf.sort_values.return_value.copy.return_value = sdf_inner

    # ── location_id column with unique() ─────────────────────────────────────
    loc_id_col = MagicMock()
    loc_id_col.unique.return_value = [loc_id]

    # ── top-level DataFrame ───────────────────────────────────────────────────
    df = MagicMock()
    df.empty = False

    def _getitem(key):
        if key == "location_id":
            return loc_id_col
        if not isinstance(key, str):   # boolean mask → station slice
            return sdf
        return MagicMock()

    df.__getitem__ = MagicMock(side_effect=_getitem)
    return df


def test_handler_sns_published_when_aqi_above_threshold():
    """SNS alert is sent when at least one forecast day has AQI > 150."""
    df = _make_station_df()
    s3_mock  = MagicMock()
    sns_mock = MagicMock()
    cw_mock  = MagicMock()

    # Forecast returns AQI-triggering PM2.5 values (~200 µg/m³ → AQI ~250)
    high_mean = [200.0] * 7
    low_lo    = [190.0] * 7
    high_hi   = [210.0] * 7

    with patch("handler._fetch_all_series", return_value=df), \
         patch("handler._fit_sarima",      return_value=MagicMock()), \
         patch("handler._forecast_sarima", return_value=(high_mean, low_lo, high_hi)), \
         patch("handler._write_parquet"), \
         patch("handler.boto3") as mock_boto3:

        mock_boto3.client.side_effect = lambda svc: {
            "s3": s3_mock, "sns": sns_mock, "cloudwatch": cw_mock
        }.get(svc, MagicMock())

        result = h.handler({}, {})

    assert result["alert_count"] > 0
    sns_mock.publish.assert_called_once()
    subject = sns_mock.publish.call_args[1]["Subject"]
    assert "Forecast Alert" in subject


def test_handler_no_sns_when_aqi_below_threshold():
    """SNS is not published when all forecast days have AQI ≤ 150."""
    df = _make_station_df()
    sns_mock = MagicMock()

    # Forecast returns safe PM2.5 values (~10 µg/m³ → AQI ~57, Moderate)
    safe_mean = [10.0] * 7
    safe_lo   = [8.0]  * 7
    safe_hi   = [12.0] * 7

    with patch("handler._fetch_all_series", return_value=df), \
         patch("handler._fit_sarima",      return_value=MagicMock()), \
         patch("handler._forecast_sarima", return_value=(safe_mean, safe_lo, safe_hi)), \
         patch("handler._write_parquet"), \
         patch("handler.boto3") as mock_boto3:

        mock_boto3.client.side_effect = lambda svc: {
            "sns": sns_mock, "cloudwatch": MagicMock(), "s3": MagicMock()
        }.get(svc, MagicMock())

        result = h.handler({}, {})

    assert result["alert_count"] == 0
    sns_mock.publish.assert_not_called()

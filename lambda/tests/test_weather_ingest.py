"""
Tests for lambda/weather_ingest/handler.py

Coverage:
  - _s3_key: raw/weather/{id}/{yyyy}/{MM}/{dd}/weather.ndjson path, zero-padded
  - _rows_for_date: NDJSON line count + field mapping for selected hour indices
  - _fetch_weather_range: builds Open-Meteo request, raises on HTTP error
  - handler: date bucketing (one S3 object per date), NDJSON content,
    backfill_days range, per-station error isolation, missing-date skip

boto3 and requests are fully mocked — no network or AWS calls.
"""

import json
import os
import sys
from datetime import date, timedelta
from unittest.mock import MagicMock, patch
import pytest

# ── Add weather_ingest/ to path ──────────────────────────────────────────────
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "weather_ingest"))

os.environ.setdefault("S3_BUCKET_NAME", "test-bucket")

sys.modules.pop("handler", None)
import handler as wi  # noqa: E402


# ── _s3_key ─────────────────────────────────────────────────────────────────────

def test_s3_key_zero_padded():
    key = wi._s3_key(7441, date(2026, 3, 5))
    assert key == "raw/weather/7441/2026/03/05/weather.ndjson"


def test_s3_key_double_digit_month_day():
    key = wi._s3_key(2539, date(2026, 12, 25))
    assert key == "raw/weather/2539/2026/12/25/weather.ndjson"


# ── _rows_for_date ────────────────────────────────────────────────────────────────

def _hourly_payload(times: list[str]) -> dict:
    n = len(times)
    return {
        "time":                  times,
        "temperature_2m":        [20.0 + i for i in range(n)],
        "relative_humidity_2m":  [70 + i for i in range(n)],
        "wind_speed_10m":        [3.0 + i for i in range(n)],
        "wind_direction_10m":    [180 + i for i in range(n)],
        "precipitation":         [0.0] * n,
        "surface_pressure":      [1010.0 + i for i in range(n)],
        "boundary_layer_height": [500.0 + i for i in range(n)],
    }


def test_rows_for_date_line_count_and_fields():
    hourly = _hourly_payload(["2026-03-05T00:00", "2026-03-05T01:00", "2026-03-05T02:00"])
    rows = wi._rows_for_date(7441, date(2026, 3, 5), hourly, indices=[0, 2])

    assert len(rows) == 2
    first = json.loads(rows[0])
    assert first["location_id"] == 7441
    assert first["date"] == "2026-03-05"
    assert first["hour_utc"] == 0
    assert first["temperature_2m"] == 20.0
    assert first["rh_2m"] == 70
    assert first["surface_pressure_hpa"] == 1010.0
    assert first["boundary_layer_height_m"] == 500.0

    third = json.loads(rows[1])
    assert third["hour_utc"] == 2
    assert third["temperature_2m"] == 22.0


# ── _fetch_weather_range ──────────────────────────────────────────────────────────

def test_fetch_weather_range_builds_request():
    resp = MagicMock()
    resp.raise_for_status.return_value = None
    resp.json.return_value = {"hourly": {}}
    with patch.object(wi.requests, "get", return_value=resp) as g:
        out = wi._fetch_weather_range(21.0, 105.8, "2026-03-04", "2026-03-05")
    assert out == {"hourly": {}}
    params = g.call_args[1]["params"]
    assert params["latitude"] == 21.0
    assert params["longitude"] == 105.8
    assert params["start_date"] == "2026-03-04"
    assert params["end_date"] == "2026-03-05"
    assert params["timezone"] == "UTC"


def test_fetch_weather_range_raises_on_http_error():
    resp = MagicMock()
    resp.raise_for_status.side_effect = Exception("HTTP 500")
    with patch.object(wi.requests, "get", return_value=resp):
        with pytest.raises(Exception):
            wi._fetch_weather_range(21.0, 105.8, "2026-03-04", "2026-03-05")


# ── handler ─────────────────────────────────────────────────────────────────────

def _single_station(monkeypatch_target=7441):
    return [{"location_id": monkeypatch_target, "lat": 21.0, "lon": 105.8}]


def test_handler_buckets_by_date():
    """Two days of hourly data → two S3 objects, one per date, NDJSON content."""
    yesterday   = date.today() - timedelta(days=1)
    day_before  = date.today() - timedelta(days=2)
    times = [
        f"{day_before.isoformat()}T00:00",
        f"{day_before.isoformat()}T01:00",
        f"{yesterday.isoformat()}T00:00",
    ]
    payload = {"hourly": _hourly_payload(times)}

    s3 = MagicMock()
    with patch.object(wi, "STATIONS", _single_station()), \
         patch.object(wi, "_fetch_weather_range", return_value=payload), \
         patch.object(wi.boto3, "client", return_value=s3):
        result = wi.handler({"backfill_days": 2}, {})

    # One put_object per date that had data → 2
    assert result["total_written"] == 2
    assert result["errors"] == 0
    assert s3.put_object.call_count == 2

    keys = {c[1]["Key"] for c in s3.put_object.call_args_list}
    assert wi._s3_key(7441, yesterday) in keys
    assert wi._s3_key(7441, day_before) in keys

    # NDJSON: each line is valid JSON; day_before object has 2 rows.
    for c in s3.put_object.call_args_list:
        body = c[1]["Body"].decode("utf-8")
        for line in body.split("\n"):
            json.loads(line)  # must not raise


def test_handler_skips_dates_without_data():
    """A target date absent from the hourly payload is skipped (logged, not written)."""
    yesterday  = date.today() - timedelta(days=1)
    # Only provide data for an unrelated date so both target dates are missing.
    times = ["2000-01-01T00:00"]
    payload = {"hourly": _hourly_payload(times)}

    s3 = MagicMock()
    with patch.object(wi, "STATIONS", _single_station()), \
         patch.object(wi, "_fetch_weather_range", return_value=payload), \
         patch.object(wi.boto3, "client", return_value=s3):
        result = wi.handler({"backfill_days": 1}, {})

    assert result["total_written"] == 0
    s3.put_object.assert_not_called()


def test_handler_isolates_station_errors():
    """One station raising does not abort the run; error_count increments."""
    yesterday = date.today() - timedelta(days=1)
    times   = [f"{yesterday.isoformat()}T00:00"]
    payload = {"hourly": _hourly_payload(times)}

    stations = [
        {"location_id": 7441, "lat": 21.0, "lon": 105.8},
        {"location_id": 2539, "lat": 21.1, "lon": 105.9},
    ]

    def _fetch(lat, lon, start, end):
        if lat == 21.0:
            raise RuntimeError("Open-Meteo timeout")
        return payload

    s3 = MagicMock()
    with patch.object(wi, "STATIONS", stations), \
         patch.object(wi, "_fetch_weather_range", side_effect=_fetch), \
         patch.object(wi.boto3, "client", return_value=s3):
        result = wi.handler({"backfill_days": 1}, {})

    assert result["errors"] == 1            # station 7441 failed
    assert result["total_written"] == 1     # station 2539 succeeded


def test_handler_backfill_days_from_env():
    """BACKFILL_DAYS env var drives the date range when event omits backfill_days."""
    yesterday  = date.today() - timedelta(days=1)
    day_before = date.today() - timedelta(days=2)
    day_3      = date.today() - timedelta(days=3)
    times = [
        f"{day_3.isoformat()}T00:00",
        f"{day_before.isoformat()}T00:00",
        f"{yesterday.isoformat()}T00:00",
    ]
    payload = {"hourly": _hourly_payload(times)}

    captured = {}

    def _fetch(lat, lon, start, end):
        captured["start"] = start
        captured["end"] = end
        return payload

    s3 = MagicMock()
    with patch.object(wi, "STATIONS", _single_station()), \
         patch.dict(os.environ, {"BACKFILL_DAYS": "3"}, clear=False), \
         patch.object(wi, "_fetch_weather_range", side_effect=_fetch), \
         patch.object(wi.boto3, "client", return_value=s3):
        result = wi.handler({}, {})

    assert captured["start"] == day_3.isoformat()
    assert captured["end"] == yesterday.isoformat()
    assert result["total_written"] == 3

"""
Tests for lambda/aqi_api/handler.py

Coverage:
  - _load_cache: miss (no file), miss (expired), hit (fresh)
  - handler: cache HIT fast-path
  - handler: cache MISS → Athena → GeoJSON schema and feature properties
  - handler: colour field populated from AQI_COLOURS
  - handler: rows with non-numeric lat/lon are silently skipped
  - handler: Athena RuntimeError → 500 response
"""

import json
import os
import sys
import time
from unittest.mock import MagicMock, patch, call
import pytest

# ── Add handler to path ────────────────────────────────────────────────────────
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "aqi_api"))

os.environ.setdefault("S3_BUCKET_NAME",   "test-bucket")
os.environ.setdefault("ATHENA_DATABASE",  "openaq_mart")
os.environ.setdefault("ATHENA_WORKGROUP", "openaq_workgroup")
os.environ.setdefault("AWS_REGION",       "ap-southeast-1")

sys.modules.pop("handler", None)  # avoid caching collision when running full suite
import handler as h  # noqa: E402  (import after path/env setup)


# ── Helpers ────────────────────────────────────────────────────────────────────

def _make_athena_client(rows: list[list[str]]) -> MagicMock:
    """Return a mock boto3 Athena client that yields the given data rows.

    rows: list of column-value lists, NOT including the header row.
    The header is auto-generated from the QUERY columns.
    """
    headers = [
        "location_id", "location_name", "city",
        "station_lat", "station_lon", "sensor_type",
        "composite_aqi", "health_category", "dominant_pollutant",
        "pm25_avg", "cigarette_equivalent", "measurement_date",
    ]

    def _make_row(values: list[str]) -> dict:
        return {"Data": [{"VarCharValue": v} for v in values]}

    header_row = _make_row(headers)
    data_rows  = [_make_row(r) for r in rows]

    page = {"ResultSet": {"Rows": [header_row] + data_rows}}

    mock_paginator = MagicMock()
    mock_paginator.paginate.return_value = [page]

    client = MagicMock()
    client.start_query_execution.return_value = {"QueryExecutionId": "test-qid-001"}
    client.get_query_execution.return_value = {
        "QueryExecution": {"Status": {"State": "SUCCEEDED"}}
    }
    client.get_paginator.return_value = mock_paginator
    return client


_GOOD_ROW = [
    "7441", "Hanoi US Embassy", "Hanoi",
    "21.0313", "105.8516", "reference",
    "72", "Moderate", "pm25",
    "20.5", "0.9", "2026-03-26",
]


# ── Cache tests ────────────────────────────────────────────────────────────────

def test_load_cache_miss_no_file(tmp_path):
    """Returns None when cache file does not exist."""
    with patch.object(h, "_CACHE_FILE", str(tmp_path / "nonexistent.json")):
        assert h._load_cache() is None


def test_load_cache_miss_expired(tmp_path):
    """Returns None when cached entry is older than CACHE_TTL_SECONDS."""
    cache_file = tmp_path / "cache.json"
    stale_at = time.time() - h.CACHE_TTL_SECONDS - 1
    cache_file.write_text(
        json.dumps({"_cached_at": stale_at, "payload": {"type": "FeatureCollection"}})
    )
    with patch.object(h, "_CACHE_FILE", str(cache_file)):
        assert h._load_cache() is None


def test_load_cache_hit(tmp_path):
    """Returns payload when cached entry is within TTL."""
    cache_file = tmp_path / "cache.json"
    payload = {"type": "FeatureCollection", "features": []}
    cache_file.write_text(
        json.dumps({"_cached_at": time.time(), "payload": payload})
    )
    with patch.object(h, "_CACHE_FILE", str(cache_file)):
        result = h._load_cache()
    assert result == payload


# ── Handler: cache HIT ─────────────────────────────────────────────────────────

def test_handler_cache_hit(tmp_path):
    """Returns 200 with X-Cache: HIT when a fresh cache entry exists."""
    cached_payload = {"type": "FeatureCollection", "updated_at": "2026-03-26", "features": []}
    cache_file = tmp_path / "cache.json"
    cache_file.write_text(
        json.dumps({"_cached_at": time.time(), "payload": cached_payload})
    )
    with patch.object(h, "_CACHE_FILE", str(cache_file)):
        response = h.handler({}, {})

    assert response["statusCode"] == 200
    assert response["headers"]["X-Cache"] == "HIT"
    assert json.loads(response["body"]) == cached_payload


# ── Handler: cache MISS → Athena ───────────────────────────────────────────────

def test_handler_geojson_schema(tmp_path):
    """GeoJSON response has FeatureCollection type and features list."""
    mock_athena = _make_athena_client([_GOOD_ROW])

    with patch.object(h, "_CACHE_FILE", str(tmp_path / "cache.json")), \
         patch("handler.boto3") as mock_boto3, \
         patch("handler.time") as mock_time:

        mock_boto3.client.return_value = mock_athena
        mock_time.time.return_value = 0.0
        mock_time.sleep = MagicMock()

        response = h.handler({}, {})

    assert response["statusCode"] == 200
    body = json.loads(response["body"])
    assert body["type"] == "FeatureCollection"
    assert "features" in body
    assert "updated_at" in body


def test_handler_feature_properties(tmp_path):
    """Each feature has geometry (Point) and all required properties."""
    mock_athena = _make_athena_client([_GOOD_ROW])

    with patch.object(h, "_CACHE_FILE", str(tmp_path / "cache.json")), \
         patch("handler.boto3") as mock_boto3, \
         patch("handler.time") as mock_time:

        mock_boto3.client.return_value = mock_athena
        mock_time.time.return_value = 0.0
        mock_time.sleep = MagicMock()

        response = h.handler({}, {})

    body    = json.loads(response["body"])
    feature = body["features"][0]

    assert feature["type"] == "Feature"
    assert feature["geometry"]["type"] == "Point"
    lon, lat = feature["geometry"]["coordinates"]
    assert lon == pytest.approx(105.8516)
    assert lat == pytest.approx(21.0313)

    props = feature["properties"]
    for key in ("location_id", "location_name", "city", "composite_aqi",
                "health_category", "dominant_pollutant", "sensor_type",
                "pm25_avg", "cigarette_equivalent", "measurement_date", "colour"):
        assert key in props, f"Missing property: {key}"


def test_handler_colour_populated(tmp_path):
    """colour field is populated from AQI_COLOURS for known health categories."""
    mock_athena = _make_athena_client([_GOOD_ROW])  # health_category = "Moderate"

    with patch.object(h, "_CACHE_FILE", str(tmp_path / "cache.json")), \
         patch("handler.boto3") as mock_boto3, \
         patch("handler.time") as mock_time:

        mock_boto3.client.return_value = mock_athena
        mock_time.time.return_value = 0.0
        mock_time.sleep = MagicMock()

        response = h.handler({}, {})

    body  = json.loads(response["body"])
    props = body["features"][0]["properties"]
    assert props["colour"] == h.AQI_COLOURS["Moderate"]


def test_handler_skips_invalid_coordinates(tmp_path):
    """Rows with non-numeric lat or lon are silently skipped."""
    bad_row = list(_GOOD_ROW)
    bad_row[3] = "not-a-number"  # station_lat
    mock_athena = _make_athena_client([bad_row])

    with patch.object(h, "_CACHE_FILE", str(tmp_path / "cache.json")), \
         patch("handler.boto3") as mock_boto3, \
         patch("handler.time") as mock_time:

        mock_boto3.client.return_value = mock_athena
        mock_time.time.return_value = 0.0
        mock_time.sleep = MagicMock()

        response = h.handler({}, {})

    body = json.loads(response["body"])
    assert body["features"] == []


def test_handler_athena_error_returns_500(tmp_path):
    """Athena RuntimeError → 500 with error body."""
    client = MagicMock()
    client.start_query_execution.return_value = {"QueryExecutionId": "qid-err"}
    client.get_query_execution.return_value = {
        "QueryExecution": {
            "Status": {
                "State": "FAILED",
                "StateChangeReason": "Table not found",
            }
        }
    }

    with patch.object(h, "_CACHE_FILE", str(tmp_path / "cache.json")), \
         patch("handler.boto3") as mock_boto3, \
         patch("handler.time") as mock_time:

        mock_boto3.client.return_value = client
        mock_time.time.return_value = 0.0
        mock_time.sleep = MagicMock()

        response = h.handler({}, {})

    assert response["statusCode"] == 500
    assert "error" in json.loads(response["body"])

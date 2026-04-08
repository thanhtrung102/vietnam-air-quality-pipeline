"""
Tests for lambda/completeness_check/handler.py

Coverage:
  - _emit_metric: calls put_metric_data with correct namespace, metric name, value
  - handler: all 21 stations present → missing=0, no SNS published
  - handler: below threshold + fresh data → SNS published, missing count correct
  - handler: below threshold + stale archive (>7 days) → SNS suppressed
  - handler: above alarm threshold but below ALERT_THRESHOLD → no SNS
  - handler: empty mart (no rows) → active=0, missing=21
  - handler: Athena query fails → returns error dict
"""

import os
import sys
from datetime import date, timedelta
from unittest.mock import MagicMock, patch, call
import pytest

# ── Add handler to path ────────────────────────────────────────────────────────
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "completeness_check"))

os.environ["S3_BUCKET_NAME"]      = "test-bucket"
os.environ["ATHENA_DATABASE"]     = "openaq_mart"
os.environ["ATHENA_WORKGROUP"]    = "openaq_workgroup"
os.environ["EXPECTED_STATIONS"]   = "21"
os.environ["ALERT_THRESHOLD"]     = "18"
os.environ["SNS_ALERT_TOPIC_ARN"] = "arn:aws:sns:ap-southeast-1:123456789012:openaq_alerts"

sys.modules.pop("handler", None)  # avoid caching collision when running full suite
import handler as h  # noqa: E402


# ── Helpers ────────────────────────────────────────────────────────────────────

def _make_athena_client(check_date: str, station_count: int) -> MagicMock:
    """Return a mock Athena client with a single-row completeness result."""
    client = MagicMock()
    client.start_query_execution.return_value = {"QueryExecutionId": "test-qid"}
    client.get_query_execution.return_value = {
        "QueryExecution": {"Status": {"State": "SUCCEEDED"}}
    }
    client.get_query_results.return_value = {
        "ResultSet": {
            "Rows": [
                {"Data": [{"VarCharValue": "check_date"},
                           {"VarCharValue": "station_count"}]},
                {"Data": [{"VarCharValue": check_date},
                           {"VarCharValue": str(station_count)}]},
            ]
        }
    }
    return client


def _make_failed_athena_client() -> MagicMock:
    client = MagicMock()
    client.start_query_execution.return_value = {"QueryExecutionId": "test-qid-fail"}
    client.get_query_execution.return_value = {
        "QueryExecution": {
            "Status": {
                "State": "FAILED",
                "StateChangeReason": "Table openaq_mart.mart_daily_aqi not found",
            }
        }
    }
    return client


def _run_handler(athena_client, cw_client=None, sns_client=None):
    """Invoke handler with patched boto3 clients, suppressing time.sleep."""
    if cw_client is None:
        cw_client = MagicMock()
    if sns_client is None:
        sns_client = MagicMock()

    client_map = {
        "athena":     athena_client,
        "cloudwatch": cw_client,
        "sns":        sns_client,
    }

    def _get_client(service):
        return client_map.get(service, MagicMock())

    with patch("handler.boto3") as mock_boto3, patch("handler.time") as mock_time:
        mock_boto3.client.side_effect = _get_client
        mock_time.time.return_value = 0.0
        mock_time.sleep = MagicMock()
        return h.handler({}, {}), cw_client, sns_client


# ── _emit_metric ───────────────────────────────────────────────────────────────

def test_emit_metric_calls_put_metric_data():
    """_emit_metric emits MissingStations to OpenAQ/Pipeline namespace."""
    cw = MagicMock()
    h._emit_metric(cw, 4)
    cw.put_metric_data.assert_called_once()
    kwargs = cw.put_metric_data.call_args[1]
    assert kwargs["Namespace"] == "OpenAQ/Pipeline"
    metric = kwargs["MetricData"][0]
    assert metric["MetricName"] == "MissingStations"
    assert metric["Value"] == 4
    assert metric["Unit"] == "Count"


# ── Handler tests ──────────────────────────────────────────────────────────────

def test_handler_all_stations_present():
    """21/21 active → missing=0, CloudWatch emitted, no SNS."""
    today = date.today().isoformat()
    result, cw, sns = _run_handler(_make_athena_client(today, 21))

    assert result["active"]   == 21
    assert result["missing"]  == 0
    assert result["expected"] == 21
    cw.put_metric_data.assert_called_once()
    sns.publish.assert_not_called()


def test_handler_below_threshold_fresh_data():
    """15 active stations + fresh data → missing=6, SNS published."""
    today = date.today().isoformat()
    result, cw, sns = _run_handler(_make_athena_client(today, 15))

    assert result["active"]  == 15
    assert result["missing"] == 6
    cw.put_metric_data.assert_called_once()
    sns.publish.assert_called_once()

    # Verify SNS subject contains station counts
    subject = sns.publish.call_args[1]["Subject"]
    assert "15" in subject and "21" in subject


def test_handler_below_threshold_stale_archive():
    """Below threshold but archive is >7 days old → SNS suppressed."""
    stale_date = (date.today() - timedelta(days=8)).isoformat()
    result, cw, sns = _run_handler(_make_athena_client(stale_date, 10))

    assert result["archive_stale"] is True
    assert result["missing"] == 11
    cw.put_metric_data.assert_called_once()  # metric still emitted
    sns.publish.assert_not_called()           # alert suppressed


def test_handler_missing_within_alarm_threshold():
    """19 active (missing=2, ≤ CloudWatch alarm threshold=3) → no SNS."""
    today = date.today().isoformat()
    result, _, sns = _run_handler(_make_athena_client(today, 19))

    # missing = 21 - 19 = 2, which is < ALERT_THRESHOLD (18 active required)
    # but active (19) >= ALERT_THRESHOLD (18), so no SNS
    assert result["active"] == 19
    sns.publish.assert_not_called()


def test_handler_empty_mart():
    """No rows in mart → active=0, missing=21, metric emitted."""
    client = MagicMock()
    client.start_query_execution.return_value = {"QueryExecutionId": "test-qid"}
    client.get_query_execution.return_value = {
        "QueryExecution": {"Status": {"State": "SUCCEEDED"}}
    }
    # Only header row, no data rows
    client.get_query_results.return_value = {
        "ResultSet": {
            "Rows": [
                {"Data": [{"VarCharValue": "check_date"},
                           {"VarCharValue": "station_count"}]},
            ]
        }
    }
    result, cw, _ = _run_handler(client)

    assert result["active"]  == 0
    assert result["missing"] == 21
    cw.put_metric_data.assert_called_once()


def test_handler_athena_failure_returns_error():
    """FAILED Athena query → handler returns error dict (no exception raised)."""
    result, _, _ = _run_handler(_make_failed_athena_client())

    assert "error" in result
    assert "not found" in result["error"].lower() or result["error"]

"""
Tests for lambda/streaming/kinesis_producer.py and lambda/streaming/handler.py

Coverage (kinesis_producer):
  - _validate_reading: sentinel -999, negative, out-of-range, unknown param, valid
  - _load_config: missing required env → ValueError; bad STATION_IDS → ValueError
    (not SystemExit, so the Lambda handler can catch it); default + override IDs
  - _api_get: retry/backoff on 429 and 5xx (retryable), no retry on 4xx
    (non-retryable), success returns JSON, exhaustion returns None
  - _put_batch_with_retry: clean success, partial failure retry, permanent failure,
    ProvisionedThroughputExceededException backoff

Coverage (handler._get_api_key — Secrets Manager → env fallback ladder):
  - no OPENAQ_SECRET_NAME → env var
  - secret present and real → secret value
  - secret == REPLACE_ME → env fallback
  - Secrets Manager ClientError → env fallback
  - caching: second call does not re-hit Secrets Manager

boto3 and requests are fully mocked — no network or AWS calls.
"""

import importlib.util
import os
import sys
from unittest.mock import MagicMock, patch
import pytest

# ── Add streaming/ to path ──────────────────────────────────────────────────────
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "streaming"))

os.environ.setdefault("AWS_REGION",          "ap-southeast-1")
os.environ.setdefault("KINESIS_STREAM_NAME", "openaq_stream")

import kinesis_producer as kp  # noqa: E402


# ── _validate_reading ────────────────────────────────────────────────────────────

class TestValidateReading:
    def test_sentinel_minus_999_rejected(self):
        ok, reason = kp._validate_reading(-999.0, "pm25")
        assert ok is False
        assert reason == "sentinel_value"

    def test_negative_rejected(self):
        ok, reason = kp._validate_reading(-5.0, "pm25")
        assert ok is False
        assert reason == "negative_value"

    def test_out_of_range_rejected(self):
        ok, reason = kp._validate_reading(500.0, "pm25")
        assert ok is False
        assert reason == "value_out_of_range"

    def test_unknown_parameter_rejected(self):
        ok, reason = kp._validate_reading(20.0, "radon")
        assert ok is False
        assert reason == "unknown_parameter"

    def test_valid_reading_accepted(self):
        ok, reason = kp._validate_reading(20.5, "pm25")
        assert ok is True
        assert reason == ""

    def test_empty_parameter_skips_param_check(self):
        # Empty parameter string bypasses the known-parameter check (enrichment
        # may not have resolved a name) but still passes range checks.
        ok, reason = kp._validate_reading(20.0, "")
        assert ok is True


# ── _load_config ──────────────────────────────────────────────────────────────────

class TestLoadConfig:
    def test_missing_required_env_raises_valueerror(self):
        with patch.dict(os.environ, {}, clear=True):
            with pytest.raises(ValueError) as exc:
                kp._load_config()
        assert "Missing required environment variables" in str(exc.value)

    def test_bad_station_ids_raises_valueerror_not_systemexit(self):
        """Malformed STATION_IDS must raise ValueError so the Lambda handler's
        `except ValueError` can return a structured error — never SystemExit."""
        env = {
            "AWS_REGION": "ap-southeast-1",
            "KINESIS_STREAM_NAME": "openaq_stream",
            "STATION_IDS": "7441,not-an-int,2539",
        }
        with patch.dict(os.environ, env, clear=True):
            with pytest.raises(ValueError):
                kp._load_config()

    def test_default_station_ids_when_unset(self):
        env = {
            "AWS_REGION": "ap-southeast-1",
            "KINESIS_STREAM_NAME": "openaq_stream",
        }
        with patch.dict(os.environ, env, clear=True):
            cfg = kp._load_config()
        assert cfg["station_ids"] == list(kp._DEFAULT_STATION_IDS)
        assert cfg["region"] == "ap-southeast-1"
        assert cfg["stream_name"] == "openaq_stream"

    def test_station_ids_override(self):
        env = {
            "AWS_REGION": "ap-southeast-1",
            "KINESIS_STREAM_NAME": "openaq_stream",
            "STATION_IDS": "111, 222 ,333",
        }
        with patch.dict(os.environ, env, clear=True):
            cfg = kp._load_config()
        assert cfg["station_ids"] == [111, 222, 333]


# ── _api_get retry / backoff ──────────────────────────────────────────────────────

def _resp(status_code: int, json_body=None, ok=None):
    r = MagicMock()
    r.status_code = status_code
    r.ok = ok if ok is not None else (200 <= status_code < 400)
    r.json.return_value = json_body if json_body is not None else {"results": []}
    return r


class TestApiGet:
    def test_success_returns_json(self):
        with patch.object(kp.requests, "get", return_value=_resp(200, {"results": [1]})) as g, \
             patch.object(kp.time, "sleep") as slept:
            out = kp._api_get("locations/7441", {}, "key")
        assert out == {"results": [1]}
        assert g.call_count == 1
        slept.assert_not_called()

    def test_429_retryable_then_success(self):
        responses = [_resp(429), _resp(200, {"results": ["ok"]})]
        with patch.object(kp.requests, "get", side_effect=responses) as g, \
             patch.object(kp.time, "sleep") as slept:
            out = kp._api_get("locations/7441", {}, "key")
        assert out == {"results": ["ok"]}
        assert g.call_count == 2
        slept.assert_called()  # backed off between the two attempts

    def test_5xx_retryable_exhausts_to_none(self):
        with patch.object(kp.requests, "get", return_value=_resp(503)) as g, \
             patch.object(kp.time, "sleep"):
            out = kp._api_get("locations/7441", {}, "key")
        assert out is None
        assert g.call_count == kp._API_MAX_RETRIES

    def test_4xx_non_retryable_no_retry(self):
        with patch.object(kp.requests, "get", return_value=_resp(404, ok=False)) as g, \
             patch.object(kp.time, "sleep") as slept:
            out = kp._api_get("locations/7441", {}, "key")
        assert out is None
        assert g.call_count == 1          # 404 is not retried
        slept.assert_not_called()

    def test_request_exception_retries(self):
        import requests as real_requests
        side = [real_requests.RequestException("boom"), _resp(200, {"results": []})]
        with patch.object(kp.requests, "get", side_effect=side) as g, \
             patch.object(kp.time, "sleep"):
            out = kp._api_get("locations/7441", {}, "key")
        assert out == {"results": []}
        assert g.call_count == 2

    def test_backoff_is_capped(self):
        """Delay never exceeds _API_MAX_DELAY across retries."""
        captured = []
        with patch.object(kp.requests, "get", return_value=_resp(500)), \
             patch.object(kp.time, "sleep", side_effect=lambda d: captured.append(d)):
            kp._api_get("locations/7441", {}, "key")
        assert all(d <= kp._API_MAX_DELAY for d in captured)


# ── _put_batch_with_retry ─────────────────────────────────────────────────────────

def _entries(n: int) -> list[dict]:
    return [{"Data": b"{}", "PartitionKey": str(i)} for i in range(n)]


class TestPutBatchWithRetry:
    def test_clean_success(self):
        client = MagicMock()
        client.put_records.return_value = {"FailedRecordCount": 0, "Records": [{}, {}]}
        ok, fail = kp._put_batch_with_retry(_entries(2), "stream", client)
        assert (ok, fail) == (2, 0)
        assert client.put_records.call_count == 1

    def test_partial_failure_retried_then_succeeds(self):
        client = MagicMock()
        # First call: record index 1 fails; second call (retry of the 1 failed): succeeds.
        client.put_records.side_effect = [
            {"FailedRecordCount": 1, "Records": [{}, {"ErrorCode": "InternalFailure"}]},
            {"FailedRecordCount": 0, "Records": [{}]},
        ]
        with patch.object(kp.time, "sleep"):
            ok, fail = kp._put_batch_with_retry(_entries(2), "stream", client, max_attempts=2)
        assert (ok, fail) == (1, 0)
        assert client.put_records.call_count == 2

    def test_permanent_failure_after_max_attempts(self):
        # Each call fails every record it is given. The retry path shrinks
        # `entries` to the failed subset, so the response must match that length.
        def _put(StreamName, Records):
            return {
                "FailedRecordCount": len(Records),
                "Records": [{"ErrorCode": "InternalFailure"} for _ in Records],
            }

        client = MagicMock()
        client.put_records.side_effect = _put
        with patch.object(kp.time, "sleep"):
            ok, fail = kp._put_batch_with_retry(_entries(2), "stream", client, max_attempts=2)
        # All records permanently fail after exhausting attempts.
        assert (ok, fail) == (0, 2)
        assert client.put_records.call_count == 2

    def test_provisioned_throughput_exceeded_backoff(self):
        from botocore.exceptions import ClientError
        err = ClientError(
            {"Error": {"Code": "ProvisionedThroughputExceededException", "Message": "slow down"}},
            "PutRecords",
        )
        client = MagicMock()
        client.put_records.side_effect = [
            err,
            {"FailedRecordCount": 0, "Records": [{}, {}]},
        ]
        with patch.object(kp.time, "sleep") as slept:
            ok, fail = kp._put_batch_with_retry(_entries(2), "stream", client, max_attempts=2)
        assert (ok, fail) == (2, 0)
        slept.assert_called()  # backed off after throughput exception
        assert client.put_records.call_count == 2

    def test_non_throughput_clienterror_fails_immediately(self):
        from botocore.exceptions import ClientError
        err = ClientError(
            {"Error": {"Code": "AccessDeniedException", "Message": "no"}},
            "PutRecords",
        )
        client = MagicMock()
        client.put_records.side_effect = err
        with patch.object(kp.time, "sleep"):
            ok, fail = kp._put_batch_with_retry(_entries(3), "stream", client, max_attempts=2)
        assert (ok, fail) == (0, 3)
        assert client.put_records.call_count == 1  # no retry on AccessDenied


# ── handler._get_api_key — Secrets Manager → env fallback ladder ──────────────────

_STREAMING_HANDLER_PATH = os.path.join(
    os.path.dirname(__file__), "..", "streaming", "handler.py"
)


def _import_streaming_handler():
    """Load streaming/handler.py by explicit path (the shared module name
    'handler' collides across Lambdas), with _cached_api_key reset to None."""
    spec = importlib.util.spec_from_file_location("streaming_handler", _STREAMING_HANDLER_PATH)
    sh = importlib.util.module_from_spec(spec)
    # kinesis_producer is already importable (streaming/ is on sys.path) so the
    # `from kinesis_producer import ...` line at the top of handler.py resolves.
    spec.loader.exec_module(sh)
    sh._cached_api_key = None
    return sh


class TestGetApiKey:
    def test_no_secret_name_uses_env_var(self):
        sh = _import_streaming_handler()
        env = {"OPENAQ_API_KEY": "env-key-123"}
        with patch.dict(os.environ, env, clear=True), \
             patch.object(sh, "boto3") as mock_boto3:
            key = sh._get_api_key()
        assert key == "env-key-123"
        mock_boto3.client.assert_not_called()  # never touched Secrets Manager

    def test_real_secret_value_preferred(self):
        sh = _import_streaming_handler()
        sm = MagicMock()
        sm.get_secret_value.return_value = {"SecretString": "real-secret-key"}
        env = {"OPENAQ_SECRET_NAME": "openaq/key", "OPENAQ_API_KEY": "env-fallback"}
        with patch.dict(os.environ, env, clear=True), \
             patch.object(sh, "boto3") as mock_boto3:
            mock_boto3.client.return_value = sm
            key = sh._get_api_key()
        assert key == "real-secret-key"

    def test_replace_me_placeholder_falls_back_to_env(self):
        sh = _import_streaming_handler()
        sm = MagicMock()
        sm.get_secret_value.return_value = {"SecretString": "REPLACE_ME"}
        env = {"OPENAQ_SECRET_NAME": "openaq/key", "OPENAQ_API_KEY": "env-fallback"}
        with patch.dict(os.environ, env, clear=True), \
             patch.object(sh, "boto3") as mock_boto3:
            mock_boto3.client.return_value = sm
            key = sh._get_api_key()
        assert key == "env-fallback"

    def test_clienterror_falls_back_to_env(self):
        from botocore.exceptions import ClientError
        sh = _import_streaming_handler()
        sm = MagicMock()
        sm.get_secret_value.side_effect = ClientError(
            {"Error": {"Code": "AccessDeniedException", "Message": "denied"}},
            "GetSecretValue",
        )
        env = {"OPENAQ_SECRET_NAME": "openaq/key", "OPENAQ_API_KEY": "env-fallback"}
        with patch.dict(os.environ, env, clear=True), \
             patch.object(sh, "boto3") as mock_boto3:
            mock_boto3.client.return_value = sm
            key = sh._get_api_key()
        assert key == "env-fallback"

    def test_result_is_cached(self):
        sh = _import_streaming_handler()
        sm = MagicMock()
        sm.get_secret_value.return_value = {"SecretString": "cached-key"}
        env = {"OPENAQ_SECRET_NAME": "openaq/key"}
        with patch.dict(os.environ, env, clear=True), \
             patch.object(sh, "boto3") as mock_boto3:
            mock_boto3.client.return_value = sm
            first  = sh._get_api_key()
            second = sh._get_api_key()
        assert first == second == "cached-key"
        sm.get_secret_value.assert_called_once()  # second call served from cache

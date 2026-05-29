"""
Tests for lambda/batch_sync/handler.py

Coverage:
  - _dst_key: archive key → raw/batch/ destination key mapping
  - _exists_in_dst: ETag match → skip (True); ETag mismatch → copy (False);
    missing object (ClientError) → copy (False)
  - _copy_object: requester-pays get_object → put_object to destination
  - _sync_station: ETag-skip logic (existing skipped, new copied), empty source,
    error capture
  - handler: aggregates copied/skipped across stations, reports failed stations

boto3 is fully mocked — no AWS calls. ThreadPoolExecutor runs the real (mocked)
work, so concurrency is exercised without network.
"""

import os
import sys
from unittest.mock import MagicMock, patch
import pytest

# ── Add batch_sync/ to path ───────────────────────────────────────────────────
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "batch_sync"))

os.environ.setdefault("S3_BUCKET_NAME", "test-dst-bucket")
os.environ.setdefault("AWS_REGION",     "ap-southeast-1")

sys.modules.pop("handler", None)
import handler as bs  # noqa: E402


# ── _dst_key ────────────────────────────────────────────────────────────────────

def test_dst_key_maps_to_raw_batch():
    src = "records/csv.gz/locationid=7441/year=2026/month=03/part-0.csv.gz"
    dst = bs._dst_key(src)
    assert dst == "raw/batch/locationid=7441/year=2026/month=03/part-0.csv.gz"


# ── _exists_in_dst ────────────────────────────────────────────────────────────────

def test_exists_in_dst_etag_match_true():
    s3 = MagicMock()
    s3.head_object.return_value = {"ETag": '"abc123"'}
    assert bs._exists_in_dst(s3, "bucket", "key", '"abc123"') is True


def test_exists_in_dst_etag_mismatch_false():
    s3 = MagicMock()
    s3.head_object.return_value = {"ETag": '"different"'}
    assert bs._exists_in_dst(s3, "bucket", "key", '"abc123"') is False


def test_exists_in_dst_missing_object_false():
    from botocore.exceptions import ClientError
    s3 = MagicMock()
    s3.head_object.side_effect = ClientError(
        {"Error": {"Code": "404", "Message": "Not Found"}}, "HeadObject"
    )
    assert bs._exists_in_dst(s3, "bucket", "key", '"abc123"') is False


# ── _copy_object ──────────────────────────────────────────────────────────────────

def test_copy_object_streams_with_requester_pays():
    s3_src = MagicMock()
    body = MagicMock()
    s3_src.get_object.return_value = {"Body": body}
    s3_dst = MagicMock()

    src_key = "records/csv.gz/locationid=7441/year=2026/month=03/part-0.csv.gz"
    bs._copy_object(s3_src, s3_dst, "dst-bucket", src_key)

    s3_src.get_object.assert_called_once_with(
        Bucket=bs.ARCHIVE_BUCKET, Key=src_key, RequestPayer="requester"
    )
    put_kwargs = s3_dst.put_object.call_args[1]
    assert put_kwargs["Bucket"] == "dst-bucket"
    assert put_kwargs["Key"] == "raw/batch/locationid=7441/year=2026/month=03/part-0.csv.gz"
    assert put_kwargs["Body"] is body


# ── _sync_station ─────────────────────────────────────────────────────────────────

def _src_object(key: str, etag: str) -> dict:
    return {"Key": key, "ETag": etag}


def _patch_session(s3_src, s3_dst):
    """Patch boto3.session.Session so _sync_station gets our mocked clients."""
    session = MagicMock()
    session.client.side_effect = lambda svc, region_name=None: (
        s3_src if region_name == bs.ARCHIVE_REGION else s3_dst
    )
    return patch.object(bs.boto3.session, "Session", return_value=session)


def test_sync_station_skips_existing_copies_new():
    """ETag-skip: object already present (matching ETag) is skipped; new one copied."""
    objs = [
        _src_object("records/csv.gz/locationid=7441/year=2026/month=03/a.csv.gz", '"e1"'),
        _src_object("records/csv.gz/locationid=7441/year=2026/month=03/b.csv.gz", '"e2"'),
    ]
    s3_src = MagicMock()
    s3_dst = MagicMock()

    with _patch_session(s3_src, s3_dst), \
         patch.object(bs, "_list_source_objects", return_value=objs), \
         patch.object(bs, "_exists_in_dst", side_effect=[True, False]) as exists, \
         patch.object(bs, "_copy_object") as copy:
        result = bs._sync_station(7441, "dst-bucket", "ap-southeast-1", "2026", "03")

    assert result == {"station_id": 7441, "copied": 1, "skipped": 1, "error": None}
    assert exists.call_count == 2
    copy.assert_called_once()  # only the non-existing object was copied


def test_sync_station_empty_source():
    s3_src = MagicMock()
    s3_dst = MagicMock()
    with _patch_session(s3_src, s3_dst), \
         patch.object(bs, "_list_source_objects", return_value=[]):
        result = bs._sync_station(7441, "dst-bucket", "ap-southeast-1", "2026", "03")
    assert result == {"station_id": 7441, "copied": 0, "skipped": 0, "error": None}


def test_sync_station_captures_error():
    s3_src = MagicMock()
    s3_dst = MagicMock()
    with _patch_session(s3_src, s3_dst), \
         patch.object(bs, "_list_source_objects", side_effect=RuntimeError("boom")):
        result = bs._sync_station(7441, "dst-bucket", "ap-southeast-1", "2026", "03")
    assert result["station_id"] == 7441
    assert result["copied"] == 0
    assert result["error"] is not None
    assert "boom" in result["error"]


# ── handler ─────────────────────────────────────────────────────────────────────

def test_handler_aggregates_results():
    """handler sums copied/skipped and tracks failed stations across all syncs."""
    def _fake_sync(station_id, dst_bucket, dst_region, year, month):
        if station_id == 7441:
            return {"station_id": station_id, "copied": 0, "skipped": 0, "error": "fail"}
        return {"station_id": station_id, "copied": 2, "skipped": 1, "error": None}

    # Restrict to two stations and a single month for a deterministic count.
    with patch.object(bs, "STATION_IDS", [7441, 2539]), \
         patch.dict(os.environ, {"SYNC_MONTHS": "1", "S3_BUCKET_NAME": "test-dst-bucket"}, clear=False), \
         patch.object(bs, "_sync_station", side_effect=_fake_sync):
        result = bs.handler({}, {})

    assert result["success"] == 1            # only station 2539 succeeded
    assert result["failed"] == ["7441"]
    assert result["copied"] == 2
    assert result["skipped"] == 1


def test_handler_all_success():
    with patch.object(bs, "STATION_IDS", [111, 222, 333]), \
         patch.dict(os.environ, {"SYNC_MONTHS": "1", "S3_BUCKET_NAME": "test-dst-bucket"}, clear=False), \
         patch.object(bs, "_sync_station",
                      return_value={"station_id": 0, "copied": 1, "skipped": 0, "error": None}):
        result = bs.handler({}, {})

    assert result["success"] == 3
    assert result["failed"] == []
    assert result["copied"] == 3

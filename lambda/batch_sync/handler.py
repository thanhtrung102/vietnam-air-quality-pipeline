"""
Batch sync Lambda handler.

Uses boto3 to implement an idempotent s3-sync equivalent:
  openaq-data-archive (us-east-1, requester-pays)
    records/csv.gz/locationid={id}/year={year}/month={month}/
  → our bucket (ap-southeast-1)
    raw/batch/locationid={id}/year={year}/month={month}/

Skips objects already present in the destination (ETag-matched HEAD check).
Processes all 21 stations in parallel via ThreadPoolExecutor (up to MAX_WORKERS
concurrent threads) to avoid the ~21× serial overhead of the previous sequential
loop. Each thread creates its own boto3 session for thread safety.
"""

import os
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError

ARCHIVE_BUCKET = "openaq-data-archive"
ARCHIVE_REGION = "us-east-1"
ARCHIVE_PREFIX = "records/csv.gz"

# Conservative worker count: Lambda has limited CPU/network; 8 concurrent S3
# connections balance throughput against the 512 MB memory and 900 s timeout.
MAX_WORKERS = 8

STATION_IDS = [
    7441, 2539, 1285357,
    2161290, 2161291, 2161292, 2161316, 2161317, 2161318,
    2161319, 2161320, 2161321, 2161323,
    4946811, 4946812, 4946813, 6123215,
    7440, 2446, 6068138, 6273386,
]


def _list_source_objects(s3_src, station_id: int, year: str, month: str) -> list[dict]:
    """List all objects in the archive for one station/year/month."""
    prefix = f"{ARCHIVE_PREFIX}/locationid={station_id}/year={year}/month={month}/"
    objects = []
    paginator = s3_src.get_paginator("list_objects_v2")
    for page in paginator.paginate(
        Bucket=ARCHIVE_BUCKET,
        Prefix=prefix,
        RequestPayer="requester",
    ):
        objects.extend(page.get("Contents", []))
    return objects


def _dst_key(src_key: str) -> str:
    """Map archive key → destination key under raw/batch/."""
    return "raw/batch/" + src_key[len(ARCHIVE_PREFIX) + 1:]  # strip "records/csv.gz/"


def _exists_in_dst(s3_dst, bucket: str, key: str, src_etag: str) -> bool:
    """Return True if the object already exists in destination with matching ETag."""
    try:
        head = s3_dst.head_object(Bucket=bucket, Key=key)
        return head["ETag"] == src_etag
    except ClientError:
        return False


def _copy_object(s3_src, s3_dst, dst_bucket: str, src_key: str) -> None:
    """Stream object from archive (requester-pays) into destination bucket."""
    response = s3_src.get_object(
        Bucket=ARCHIVE_BUCKET,
        Key=src_key,
        RequestPayer="requester",
    )
    # Stream body directly to put_object rather than buffering the full file
    # in Lambda memory. boto3 accepts a streaming Body for put_object.
    dst = _dst_key(src_key)
    s3_dst.put_object(Bucket=dst_bucket, Key=dst, Body=response["Body"])


def _sync_station(station_id: int, dst_bucket: str, dst_region: str, year: str, month: str) -> dict:
    """
    Sync one station for the given year/month. Creates its own boto3 session
    so threads do not share client state.
    Returns a result dict with keys: station_id, copied, skipped, error.
    """
    # Each thread needs its own session — boto3 clients are not thread-safe
    session = boto3.session.Session()
    s3_src = session.client("s3", region_name=ARCHIVE_REGION)
    s3_dst = session.client("s3", region_name=dst_region)

    try:
        objects = _list_source_objects(s3_src, station_id, year, month)
        if not objects:
            print(f"INFO no archive files for station {station_id} {year}/{month}")
            return {"station_id": station_id, "copied": 0, "skipped": 0, "error": None}

        copied = skipped = 0
        for obj in objects:
            src_key = obj["Key"]
            dst = _dst_key(src_key)
            if _exists_in_dst(s3_dst, dst_bucket, dst, obj["ETag"]):
                skipped += 1
                continue
            _copy_object(s3_src, s3_dst, dst_bucket, src_key)
            copied += 1

        return {"station_id": station_id, "copied": copied, "skipped": skipped, "error": None}

    except Exception as exc:
        print(f"ERROR station {station_id}: {exc}", file=sys.stderr)
        return {"station_id": station_id, "copied": 0, "skipped": 0, "error": str(exc)}


def handler(event, context):
    dst_bucket = os.environ["S3_BUCKET_NAME"]
    dst_region = os.environ.get("AWS_REGION", "ap-southeast-1")
    now = datetime.now(timezone.utc)
    year = str(now.year)
    month = str(now.month).zfill(2)

    success = 0
    failed = []
    total_copied = 0
    total_skipped = 0

    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as pool:
        futures = {
            pool.submit(_sync_station, station_id, dst_bucket, dst_region, year, month): station_id
            for station_id in STATION_IDS
        }
        for future in as_completed(futures):
            result = future.result()
            if result["error"]:
                failed.append(str(result["station_id"]))
            else:
                success += 1
                total_copied += result["copied"]
                total_skipped += result["skipped"]

    print(
        f"Batch sync complete: success={success} failed={len(failed)} "
        f"copied={total_copied} skipped={total_skipped}"
    )
    if failed:
        print(f"Failed stations: {failed}")
    return {"success": success, "failed": failed, "copied": total_copied, "skipped": total_skipped}

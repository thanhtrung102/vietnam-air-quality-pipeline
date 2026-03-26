"""
Batch sync Lambda handler.

Uses boto3 to implement an idempotent s3-sync equivalent:
  openaq-data-archive (us-east-1, requester-pays)
    records/csv.gz/locationid={id}/year={year}/month={month}/
  → our bucket (ap-southeast-1)
    raw/batch/locationid={id}/year={year}/month={month}/

Skips objects already present in the destination (ETag-matched HEAD check).
"""

import os
import sys
from datetime import datetime

import boto3
from botocore.exceptions import ClientError

ARCHIVE_BUCKET = "openaq-data-archive"
ARCHIVE_REGION = "us-east-1"
ARCHIVE_PREFIX = "records/csv.gz"

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
    """Download from archive (requester-pays) and upload to destination."""
    response = s3_src.get_object(
        Bucket=ARCHIVE_BUCKET,
        Key=src_key,
        RequestPayer="requester",
    )
    body = response["Body"].read()
    dst = _dst_key(src_key)
    s3_dst.put_object(Bucket=dst_bucket, Key=dst, Body=body)


def handler(event, context):
    dst_bucket = os.environ["S3_BUCKET_NAME"]
    dst_region = os.environ.get("AWS_REGION", "ap-southeast-1")
    now = datetime.utcnow()
    year = str(now.year)
    month = str(now.month).zfill(2)

    s3_src = boto3.client("s3", region_name=ARCHIVE_REGION)
    s3_dst = boto3.client("s3", region_name=dst_region)

    success = 0
    failed = []
    total_copied = 0
    total_skipped = 0

    for station_id in STATION_IDS:
        try:
            objects = _list_source_objects(s3_src, station_id, year, month)
            if not objects:
                print(f"INFO no archive files for station {station_id} {year}/{month}")
                success += 1
                continue

            for obj in objects:
                src_key = obj["Key"]
                dst = _dst_key(src_key)
                if _exists_in_dst(s3_dst, dst_bucket, dst, obj["ETag"]):
                    total_skipped += 1
                    continue
                _copy_object(s3_src, s3_dst, dst_bucket, src_key)
                total_copied += 1

            success += 1

        except Exception as exc:
            failed.append(str(station_id))
            print(f"ERROR station {station_id}: {exc}", file=sys.stderr)

    print(
        f"Batch sync complete: success={success} failed={len(failed)} "
        f"copied={total_copied} skipped={total_skipped}"
    )
    if failed:
        print(f"Failed stations: {failed}")
    return {"success": success, "failed": failed, "copied": total_copied, "skipped": total_skipped}

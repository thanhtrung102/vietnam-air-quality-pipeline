"""
handler.py — AWS Lambda entry point for the OpenAQ Kinesis producer.

Triggered every 2 hours by EventBridge Scheduler.
All business logic lives in kinesis_producer.py (packaged alongside this file
by lambda/build.sh).

Environment variables (set as Lambda env vars):
    OPENAQ_API_KEY      — OpenAQ v3 API key
    KINESIS_STREAM_NAME — Kinesis stream name (e.g. openaq_stream)

AWS_REGION is injected automatically by the Lambda runtime — do not set it
as a Lambda environment variable (AWS reserves that name).
"""
import logging

import boto3

from kinesis_producer import (
    _load_config,
    build_sensor_cache,
    fetch_latest_measurements,
    put_to_kinesis,
)

log = logging.getLogger(__name__)
log.setLevel(logging.INFO)

# Module-level state persists across warm Lambda invocations (container reuse).
# On a cold start these are None and get initialised once inside lambda_handler.
_cfg = None
_kinesis_client = None
_sensor_cache = None


def lambda_handler(event, context):
    """Fetch latest OpenAQ measurements for Vietnamese stations and publish to Kinesis."""
    global _cfg, _kinesis_client, _sensor_cache

    # Cold-start path — skipped on warm invocations
    if _cfg is None:
        _cfg = _load_config()
        _kinesis_client = boto3.client("kinesis", region_name=_cfg["region"])
        _sensor_cache = build_sensor_cache(_cfg["station_ids"], _cfg["api_key"])

    records = fetch_latest_measurements(
        _cfg["station_ids"], _cfg["api_key"], _sensor_cache
    )

    if not records:
        log.info("no new records to publish")
        return {"success": 0, "failed": 0}

    success, failed = put_to_kinesis(records, _cfg["stream_name"], _kinesis_client)
    log.info(
        "published — success=%d  failed=%d  stream=%s",
        success,
        failed,
        _cfg["stream_name"],
    )
    return {"success": success, "failed": failed}

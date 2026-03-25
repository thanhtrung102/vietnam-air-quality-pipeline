"""
kinesis_producer.py — Fetch latest OpenAQ measurements for Vietnamese stations
and publish them to a Kinesis Data Stream.

Strategy:
  1. At startup, call GET /v3/locations/{id} for each station to build a
     sensorsId → {parameter, units, location_name, lat, lon} lookup cache.
  2. On each poll, call GET /v3/locations/{id}/latest for each station and
     enrich each reading with the cached sensor metadata.
  3. Publish the flat records as JSON to the Kinesis stream.

Kinesis Firehose consumes the stream and writes to
  s3://…/raw/stream/{yyyy}/{MM}/{dd}/{HH}/

Environment variables (required):
    OPENAQ_API_KEY        OpenAQ v3 API key
    AWS_REGION            AWS region (e.g. ap-southeast-1)
    KINESIS_STREAM_NAME   Kinesis stream name (e.g. openaq_stream)

Optional:
    STATION_IDS           Comma-separated location IDs; defaults to all 20 VN stations.

Usage:
    python kinesis_producer.py            # run once
    python kinesis_producer.py --loop     # poll every 2 hours indefinitely
"""

import json
import logging
import os
import sys
import time
from datetime import datetime, timezone

import boto3
import requests
from botocore.exceptions import ClientError

# ── Logging ───────────────────────────────────────────────────────────────────

logging.basicConfig(
    format="%(asctime)s %(levelname)s %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S",
    level=logging.INFO,
    stream=sys.stdout,
)
log = logging.getLogger(__name__)

# ── Config ────────────────────────────────────────────────────────────────────

_REQUIRED_ENV = ("OPENAQ_API_KEY", "AWS_REGION", "KINESIS_STREAM_NAME")

# 20 confirmed Vietnamese station IDs — overridable via STATION_IDS env var
_DEFAULT_STATION_IDS = [
    7441, 2539, 1285357,
    2161290, 2161291, 2161292, 2161316, 2161317, 2161318,
    2161319, 2161320, 2161321, 2161323,
    4946812, 4946813, 6123215,
    7440, 2446, 6068138, 6273386,
]

OPENAQ_BASE_URL = "https://api.openaq.org/v3"
POLL_INTERVAL   = 2 * 3600   # 2 hours between polls in --loop mode
BATCH_SIZE      = 500        # max records per Kinesis PutRecords call
RETRY_BACKOFF   = 5          # seconds before retrying failed Kinesis records


def _load_config() -> dict:
    """Read and validate required environment variables."""
    missing = [k for k in _REQUIRED_ENV if not os.environ.get(k)]
    if missing:
        raise ValueError(f"Missing required environment variables: {missing}")

    raw_ids = os.environ.get("STATION_IDS", "")
    if raw_ids.strip():
        try:
            station_ids = [int(x.strip()) for x in raw_ids.split(",") if x.strip()]
        except ValueError:
            log.error("STATION_IDS must be comma-separated integers, got: %s", raw_ids)
            sys.exit(1)
    else:
        station_ids = list(_DEFAULT_STATION_IDS)

    return {
        "api_key":     os.environ["OPENAQ_API_KEY"],
        "region":      os.environ["AWS_REGION"],
        "stream_name": os.environ["KINESIS_STREAM_NAME"],
        "station_ids": station_ids,
    }


# ── OpenAQ API helpers ────────────────────────────────────────────────────────

def _api_get(path: str, params: dict, api_key: str) -> dict | None:
    """GET one OpenAQ v3 endpoint; returns parsed JSON or None on error."""
    try:
        resp = requests.get(
            f"{OPENAQ_BASE_URL}/{path}",
            params=params,
            headers={"X-API-Key": api_key},
            timeout=30,
        )
        resp.raise_for_status()
        return resp.json()
    except requests.HTTPError as exc:
        log.error("API HTTP error %s %s: %s", path, params, exc)
    except requests.RequestException as exc:
        log.error("API request failed %s: %s", path, exc)
    return None


def build_sensor_cache(station_ids: list[int], api_key: str) -> dict[int, dict]:
    """
    For each station, fetch /v3/locations/{id} and build a mapping:
      sensorsId → {parameter, units, location_name, lat, lon, location_id}

    Called once at startup and reused on every poll.
    """
    cache: dict[int, dict] = {}

    for station_id in station_ids:
        data = _api_get(f"locations/{station_id}", {}, api_key)
        if not data or not data.get("results"):
            log.warning("no location metadata for station %s", station_id)
            continue

        loc = data["results"][0]
        coords = loc.get("coordinates") or {}
        name   = loc.get("name", "")

        for sensor in loc.get("sensors", []):
            sensor_id = sensor.get("id")
            param     = sensor.get("parameter") or {}
            if sensor_id:
                cache[sensor_id] = {
                    "parameter":     param.get("name", ""),
                    "units":         param.get("units", ""),
                    "location_name": name,
                    "lat":           coords.get("latitude"),
                    "lon":           coords.get("longitude"),
                    "location_id":   station_id,
                }

    log.info("sensor cache built — %d sensors across %d stations", len(cache), len(station_ids))
    return cache


def fetch_latest_measurements(
    station_ids: list[int],
    api_key: str,
    sensor_cache: dict[int, dict],
) -> list[dict]:
    """
    For each station call GET /v3/locations/{id}/latest and flatten each
    reading into the archive-compatible schema using the sensor cache for
    parameter/units enrichment. Skips sentinel value -999.0.
    """
    records: list[dict] = []
    ingested_at = datetime.now(timezone.utc).isoformat()

    for station_id in station_ids:
        data = _api_get(f"locations/{station_id}/latest", {}, api_key)
        if not data or not data.get("results"):
            continue

        for reading in data["results"]:
            try:
                value = float(reading.get("value", -999.0))
                if value == -999.0:
                    continue

                sensor_id = reading.get("sensorsId")
                meta      = sensor_cache.get(sensor_id, {})

                dt = reading.get("datetime") or {}
                dt_str = dt.get("utc", "") if isinstance(dt, dict) else str(dt)

                coords = reading.get("coordinates") or {}
                lat = coords.get("latitude")  or meta.get("lat")
                lon = coords.get("longitude") or meta.get("lon")

                records.append({
                    "location_id":  station_id,
                    "sensors_id":   sensor_id,
                    "location":     meta.get("location_name", ""),
                    "datetime":     dt_str,
                    "lat":          lat,
                    "lon":          lon,
                    "parameter":    meta.get("parameter", ""),
                    "units":        meta.get("units", ""),
                    "value":        value,
                    "ingested_at":  ingested_at,
                })
            except Exception as exc:
                log.warning("normalise failed for station %s reading: %s — %s", station_id, reading, exc)

    log.info("fetched %d valid reading(s) (sentinel -999.0 excluded)", len(records))
    return records


# ── Kinesis ───────────────────────────────────────────────────────────────────

def put_to_kinesis(
    records: list[dict],
    stream_name: str,
    kinesis_client,
) -> tuple[int, int]:
    """
    Batch-put records in groups of BATCH_SIZE (max 500).
    Retries failed records once after RETRY_BACKOFF seconds.
    Handles ProvisionedThroughputExceededException with exponential backoff.
    Returns (total_success, total_failed).
    """
    total_success = total_failed = 0

    for start in range(0, len(records), BATCH_SIZE):
        batch = records[start : start + BATCH_SIZE]
        entries = [
            {
                "Data":         json.dumps(r).encode("utf-8"),
                "PartitionKey": str(r.get("location_id", "unknown")),
            }
            for r in batch
        ]
        ok, fail = _put_batch_with_retry(entries, stream_name, kinesis_client)
        total_success += ok
        total_failed  += fail

    return total_success, total_failed


def _put_batch_with_retry(
    entries: list[dict],
    stream_name: str,
    kinesis_client,
    max_attempts: int = 2,
) -> tuple[int, int]:
    backoff = RETRY_BACKOFF

    for attempt in range(1, max_attempts + 1):
        try:
            resp = kinesis_client.put_records(
                StreamName=stream_name,
                Records=entries,
            )
        except ClientError as exc:
            code = exc.response["Error"]["Code"]
            if code == "ProvisionedThroughputExceededException" and attempt < max_attempts:
                log.warning("ProvisionedThroughputExceededException — backoff %ds (attempt %d/%d)",
                            backoff, attempt, max_attempts)
                time.sleep(backoff)
                backoff *= 2
                continue
            log.error("Kinesis PutRecords ClientError: %s", exc)
            return 0, len(entries)

        failed_count = resp.get("FailedRecordCount", 0)
        if failed_count == 0:
            return len(entries), 0

        failed_entries = [
            entries[i]
            for i, r in enumerate(resp["Records"])
            if "ErrorCode" in r
        ]
        error_codes = {r["ErrorCode"] for r in resp["Records"] if "ErrorCode" in r}
        log.warning("%d record(s) failed (attempt %d/%d) error codes: %s",
                    failed_count, attempt, max_attempts, error_codes)

        if attempt < max_attempts:
            log.info("retrying %d failed record(s) after %ds", len(failed_entries), backoff)
            time.sleep(backoff)
            entries = failed_entries
            backoff *= 2
        else:
            log.error("%d record(s) permanently failed", len(failed_entries))
            return len(entries) - len(failed_entries), len(failed_entries)

    return len(entries), 0


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    import argparse
    p = argparse.ArgumentParser(description="Publish latest OpenAQ VN measurements to Kinesis")
    p.add_argument("--loop", action="store_true", help="Poll every 2 hours continuously")
    args = p.parse_args()

    cfg     = _load_config()
    kinesis = boto3.client("kinesis", region_name=cfg["region"])

    log.info("producer started — stream=%s  stations=%d",
             cfg["stream_name"], len(cfg["station_ids"]))

    # Build sensor cache once; reused across all poll cycles
    sensor_cache = build_sensor_cache(cfg["station_ids"], cfg["api_key"])

    def run_once():
        records = fetch_latest_measurements(cfg["station_ids"], cfg["api_key"], sensor_cache)
        if not records:
            log.info("no records to publish")
            return

        success, failed = put_to_kinesis(records, cfg["stream_name"], kinesis)
        log.info("published — success=%d  failed=%d  stream=%s",
                 success, failed, cfg["stream_name"])

    if args.loop:
        log.info("loop mode — polling every %ds (Ctrl-C to stop)", POLL_INTERVAL)
        while True:
            try:
                run_once()
            except KeyboardInterrupt:
                log.info("interrupted — exiting")
                sys.exit(0)
            except Exception as exc:
                log.error("unhandled error in poll cycle: %s", exc)
            time.sleep(POLL_INTERVAL)
    else:
        run_once()


if __name__ == "__main__":
    main()

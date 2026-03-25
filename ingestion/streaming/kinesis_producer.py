"""
kinesis_producer.py — Fetch recent OpenAQ measurements for Vietnamese stations
and publish them to a Kinesis Data Stream.

Reads the last 2 hours of measurements from the OpenAQ v3 API and puts each
record onto the stream as a JSON payload. Kinesis Firehose then buffers and
writes the records to s3://…/raw/stream/{yyyy}/{MM}/{dd}/{HH}/.

Environment variables (required):
    OPENAQ_API_KEY        OpenAQ v3 API key
    AWS_REGION            AWS region (e.g. ap-southeast-1)
    KINESIS_STREAM_NAME   Kinesis stream name (e.g. openaq_stream)

Optional:
    STATION_IDS           Comma-separated list of OpenAQ location IDs.
                          Defaults to the 20 confirmed Vietnamese stations.

Usage:
    python kinesis_producer.py            # run once
    python kinesis_producer.py --loop     # poll every 2 hours indefinitely
"""

import json
import logging
import os
import sys
import time
from datetime import datetime, timedelta, timezone

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

# 20 confirmed Vietnamese station IDs — used when STATION_IDS env var is unset
_DEFAULT_STATION_IDS = [
    7441, 2539, 1285357,
    2161290, 2161291, 2161292, 2161316, 2161317, 2161318,
    2161319, 2161320, 2161321, 2161323,
    4946812, 4946813, 6123215,
    7440, 2446, 6068138, 6273386,
]

OPENAQ_BASE_URL = "https://api.openaq.org/v3"
LOOKBACK_HOURS  = 2        # how far back to fetch on each poll
BATCH_SIZE      = 500      # max records per Kinesis PutRecords call
RETRY_BACKOFF   = 5        # seconds before retrying failed Kinesis records


def _load_config() -> dict:
    """Read and validate required environment variables. Exit with a clear
    message if any are missing rather than raising a cryptic KeyError."""
    missing = [k for k in _REQUIRED_ENV if not os.environ.get(k)]
    if missing:
        for key in missing:
            log.error("Missing required environment variable: %s", key)
        sys.exit(1)

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
        "api_key":      os.environ["OPENAQ_API_KEY"],
        "region":       os.environ["AWS_REGION"],
        "stream_name":  os.environ["KINESIS_STREAM_NAME"],
        "station_ids":  station_ids,
    }


# ── OpenAQ API ────────────────────────────────────────────────────────────────

def fetch_recent_measurements(station_ids: list[int], api_key: str) -> list[dict]:
    """
    Fetch measurements for the given station IDs from the last LOOKBACK_HOURS.

    Returns a list of normalised flat records (same schema as the archive CSV).
    Filters out sentinel value -999.0.
    """
    date_from = (
        datetime.now(timezone.utc) - timedelta(hours=LOOKBACK_HOURS)
    ).strftime("%Y-%m-%dT%H:%M:%SZ")

    headers  = {"X-API-Key": api_key}
    params   = {
        "location_id": ",".join(str(i) for i in station_ids),
        "limit":       1000,
        "date_from":   date_from,
        "order_by":    "datetime",
        "sort":        "desc",
    }

    records = []
    page    = 1

    while True:
        params["page"] = page
        try:
            resp = requests.get(
                f"{OPENAQ_BASE_URL}/measurements",
                params=params,
                headers=headers,
                timeout=30,
            )
            resp.raise_for_status()
        except requests.HTTPError as exc:
            log.error("OpenAQ API HTTP error (page %d): %s", page, exc)
            break
        except requests.RequestException as exc:
            log.error("OpenAQ API request failed (page %d): %s", page, exc)
            break

        body    = resp.json()
        results = body.get("results", [])
        if not results:
            break

        for r in results:
            record = _normalise(r)
            if record is not None:
                records.append(record)

        meta  = body.get("meta", {})
        found = meta.get("found", 0)
        if page * 1000 >= found or len(results) < 1000:
            break
        page += 1

    log.info(
        "fetched %d valid record(s) since %s (sentinel -999.0 excluded)",
        len(records), date_from,
    )
    return records


def _normalise(raw: dict) -> dict | None:
    """Flatten one OpenAQ v3 measurement into the archive-compatible schema."""
    try:
        value = float(raw.get("value", -999.0))
        if value == -999.0:
            return None

        dt = raw.get("date") or raw.get("datetime") or {}
        dt_str = dt.get("utc", "") if isinstance(dt, dict) else str(dt)

        coords    = raw.get("coordinates") or {}
        parameter = raw.get("parameter", "")
        if isinstance(parameter, dict):
            parameter = parameter.get("name", "")

        return {
            "location_id":  raw.get("locationId") or raw.get("location_id"),
            "sensors_id":   raw.get("sensorsId")  or raw.get("sensors_id"),
            "location":     raw.get("location", ""),
            "datetime":     dt_str,
            "lat":          coords.get("latitude"),
            "lon":          coords.get("longitude"),
            "parameter":    parameter,
            "units":        raw.get("unit", ""),
            "value":        value,
            "ingested_at":  datetime.now(timezone.utc).isoformat(),
        }
    except Exception as exc:
        log.warning("normalise failed: %s — raw=%s", exc, raw)
        return None


# ── Kinesis ───────────────────────────────────────────────────────────────────

def put_to_kinesis(
    records: list[dict],
    stream_name: str,
    kinesis_client,
) -> tuple[int, int]:
    """
    Batch-put records to Kinesis in groups of BATCH_SIZE (max 500).

    - Uses location_id as the partition key for shard routing.
    - If FailedRecordCount > 0, logs the failures and retries once after
      RETRY_BACKOFF seconds.
    - Catches ProvisionedThroughputExceededException with exponential backoff.

    Returns (total_success, total_failed).
    """
    total_success = total_failed = 0

    for batch_start in range(0, len(records), BATCH_SIZE):
        batch = records[batch_start : batch_start + BATCH_SIZE]

        entries = [
            {
                "Data":         json.dumps(r).encode("utf-8"),
                "PartitionKey": str(r.get("location_id", "unknown")),
            }
            for r in batch
        ]

        success, failed = _put_batch_with_retry(entries, stream_name, kinesis_client)
        total_success += success
        total_failed  += failed

    return total_success, total_failed


def _put_batch_with_retry(
    entries: list[dict],
    stream_name: str,
    kinesis_client,
    attempt: int = 1,
    max_attempts: int = 2,
) -> tuple[int, int]:
    """Put one batch; retry failed records once after RETRY_BACKOFF seconds."""
    backoff = RETRY_BACKOFF

    for attempt in range(1, max_attempts + 1):
        try:
            resp = kinesis_client.put_records(
                StreamName=stream_name,
                Records=entries,
            )
        except ClientError as exc:
            code = exc.response["Error"]["Code"]
            if code == "ProvisionedThroughputExceededException":
                if attempt < max_attempts:
                    log.warning(
                        "ProvisionedThroughputExceededException — backing off %ds (attempt %d/%d)",
                        backoff, attempt, max_attempts,
                    )
                    time.sleep(backoff)
                    backoff *= 2
                    continue
            log.error("Kinesis PutRecords ClientError: %s", exc)
            return 0, len(entries)

        failed_count = resp.get("FailedRecordCount", 0)
        if failed_count == 0:
            return len(entries), 0

        # Collect only the failed entries for retry
        failed_entries = [
            entries[i]
            for i, r in enumerate(resp["Records"])
            if "ErrorCode" in r
        ]
        log.warning(
            "%d record(s) failed (attempt %d/%d) — error codes: %s",
            failed_count,
            attempt,
            max_attempts,
            list({r["ErrorCode"] for r in resp["Records"] if "ErrorCode" in r}),
        )

        if attempt < max_attempts:
            log.info("retrying %d failed record(s) after %ds", len(failed_entries), backoff)
            time.sleep(backoff)
            entries = failed_entries
            backoff *= 2
        else:
            log.error("%d record(s) permanently failed after %d attempts", len(failed_entries), max_attempts)
            return len(entries) - len(failed_entries), len(failed_entries)

    return len(entries), 0   # unreachable, satisfies type checkers


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    import argparse
    p = argparse.ArgumentParser(description="Publish recent OpenAQ VN measurements to Kinesis")
    p.add_argument("--loop", action="store_true", help="Poll every LOOKBACK_HOURS continuously")
    args = p.parse_args()

    cfg = _load_config()
    kinesis = boto3.client("kinesis", region_name=cfg["region"])

    log.info(
        "producer started — stream=%s  stations=%d  lookback=%dh",
        cfg["stream_name"], len(cfg["station_ids"]), LOOKBACK_HOURS,
    )

    def run_once():
        records = fetch_recent_measurements(cfg["station_ids"], cfg["api_key"])
        if not records:
            log.info("no new records to publish")
            return

        success, failed = put_to_kinesis(records, cfg["stream_name"], kinesis)
        log.info(
            "published — success=%d  failed=%d  stream=%s",
            success, failed, cfg["stream_name"],
        )

    if args.loop:
        interval = LOOKBACK_HOURS * 3600
        log.info("loop mode — polling every %ds (Ctrl-C to stop)", interval)
        while True:
            try:
                run_once()
            except KeyboardInterrupt:
                log.info("interrupted — exiting")
                sys.exit(0)
            except Exception as exc:
                log.error("unhandled error in poll cycle: %s", exc)
            time.sleep(interval)
    else:
        run_once()


if __name__ == "__main__":
    main()

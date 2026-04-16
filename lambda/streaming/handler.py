import os
import sys

import boto3
from botocore.exceptions import ClientError
from kinesis_producer import _load_config, build_sensor_cache, fetch_latest_measurements, put_to_kinesis

# ── Gap 2: Secrets Manager key retrieval ──────────────────────────────────────
# Reads the OpenAQ API key from Secrets Manager on cold start and caches it for
# the container lifetime. Falls back to OPENAQ_API_KEY env var if:
#   - OPENAQ_SECRET_NAME is not set, or
#   - Secrets Manager is unreachable (VPC misconfiguration, permissions error), or
#   - The secret value is the placeholder string "REPLACE_ME".
# This safe-transition design lets the Lambda function work during the rollout
# period before the real key is injected via CLI post-deploy.

_cached_api_key: str | None = None


def _get_api_key() -> str | None:
    global _cached_api_key
    if _cached_api_key is not None:
        return _cached_api_key

    secret_name = os.environ.get("OPENAQ_SECRET_NAME")
    if secret_name:
        try:
            sm = boto3.client("secretsmanager")
            resp = sm.get_secret_value(SecretId=secret_name)
            value = resp.get("SecretString", "")
            if value and value != "REPLACE_ME":
                _cached_api_key = value
                return _cached_api_key
            print(f"INFO: Secrets Manager secret '{secret_name}' contains placeholder — "
                  "falling back to OPENAQ_API_KEY env var")
        except ClientError as exc:
            print(f"WARNING: Secrets Manager unavailable ({exc.response['Error']['Code']}) "
                  "— falling back to OPENAQ_API_KEY env var")
        except Exception as exc:
            print(f"WARNING: Secrets Manager error: {exc} — falling back to OPENAQ_API_KEY env var")

    _cached_api_key = os.environ.get("OPENAQ_API_KEY")
    return _cached_api_key


def handler(event, context):
    try:
        cfg = _load_config()
    except ValueError as e:
        print(f"ERROR: {e}")
        return {"success": 0, "failed": 0, "error": str(e)}

    # Gap 2: override api_key from Secrets Manager (falls back to env var)
    api_key = _get_api_key()
    if not api_key:
        print("ERROR: no API key available from Secrets Manager or OPENAQ_API_KEY env var")
        return {"success": 0, "failed": 0, "error": "missing api key"}
    cfg["api_key"] = api_key

    kinesis = boto3.client("kinesis", region_name=cfg["region"])
    sensor_cache = build_sensor_cache(cfg["station_ids"], cfg["api_key"])
    records = fetch_latest_measurements(cfg["station_ids"], cfg["api_key"], sensor_cache)

    if not records:
        print("no records to publish")
        return {"success": 0, "failed": 0}

    success, failed = put_to_kinesis(records, cfg["stream_name"], kinesis)
    print(f"published: success={success} failed={failed}")
    return {"success": success, "failed": failed}
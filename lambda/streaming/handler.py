import sys
sys.path.insert(0, "/var/task")
import boto3
from kinesis_producer import _load_config, build_sensor_cache, fetch_latest_measurements, put_to_kinesis

def handler(event, context):
    try:
        cfg = _load_config()
    except ValueError as e:
        print(f"ERROR: {e}")
        return {"success": 0, "failed": 0, "error": str(e)}

    kinesis = boto3.client("kinesis", region_name=cfg["region"])
    sensor_cache = build_sensor_cache(cfg["station_ids"], cfg["api_key"])
    records = fetch_latest_measurements(cfg["station_ids"], cfg["api_key"], sensor_cache)

    if not records:
        print("no records to publish")
        return {"success": 0, "failed": 0}

    success, failed = put_to_kinesis(records, cfg["stream_name"], kinesis)
    print(f"published: success={success} failed={failed}")
    return {"success": success, "failed": failed}

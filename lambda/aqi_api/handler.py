"""
aqi_api — Lambda-backed API returning latest composite AQI per station as GeoJSON.

Queries mart_daily_aqi via Athena for the most recent date with data,
then returns a GeoJSON FeatureCollection for the Leaflet map.

Environment variables:
  S3_BUCKET_NAME      — project S3 bucket for Athena staging output
  ATHENA_DATABASE     — Glue database (default: openaq_mart)
  ATHENA_WORKGROUP    — Athena workgroup (default: openaq_workgroup)

Caching:
  The GeoJSON payload is cached in /tmp between warm Lambda invocations for up
  to CACHE_TTL_SECONDS (3600 s). The underlying mart is rebuilt daily, so hourly
  staleness is acceptable. Cache is keyed on the day (UTC) so a dbt rebuild at
  midnight automatically invalidates it on the next invocation.

Response shape (GeoJSON FeatureCollection):
  {
    "type": "FeatureCollection",
    "updated_at": "2026-03-26",
    "features": [
      {
        "type": "Feature",
        "geometry": { "type": "Point", "coordinates": [lon, lat] },
        "properties": {
          "location_id": 7441,
          "location_name": "Hanoi (US Embassy)",
          "city": "Hanoi",
          "composite_aqi": 88,
          "health_category": "Moderate",
          "dominant_pollutant": "pm25",
          "sensor_type": "reference",
          "pm25_avg": 27.3,
          "cigarette_equivalent": 1.2,
          "measurement_date": "2026-03-26"
        }
      }
    ]
  }
"""

import json
import os
import sys
import time
from datetime import datetime, timezone

import boto3

# local dev: lambda/shared/ is not on sys.path; Lambda runtime: athena_utils.py
# is copied to the package root by build.sh so the import resolves there.
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "shared"))
from athena_utils import AthenaConfig, run_query  # noqa: E402

# Partition-pruned query: the inner subquery is bounded to the last 7 days so
# Athena only scans recent partitions instead of the full historical table.
# 7 days handles stations with up to 6 days of data lag (archive latency ~72 h)
# while keeping the scan minimal. The outer join then picks the latest per station.
QUERY = """
SELECT
    a.location_id,
    a.location_name,
    a.city,
    a.station_lat,
    a.station_lon,
    a.sensor_type,
    a.composite_aqi,
    a.health_category,
    a.dominant_pollutant,
    a.pm25_avg,
    a.cigarette_equivalent,
    CAST(a.measurement_date AS VARCHAR) AS measurement_date
FROM openaq_mart.mart_daily_aqi a
INNER JOIN (
    SELECT location_id, MAX(measurement_date) AS latest_date
    FROM openaq_mart.mart_daily_aqi
    WHERE measurement_date >= DATE_ADD('day', -7, CURRENT_DATE)
    GROUP BY location_id
) latest
    ON a.location_id      = latest.location_id
    AND a.measurement_date = latest.latest_date
ORDER BY a.city, a.location_name
"""

# AQI colour palette (EPA standard)
AQI_COLOURS = {
    "Good":                          "#00e400",
    "Moderate":                      "#ffff00",
    "Unhealthy for Sensitive Groups": "#ff7e00",
    "Unhealthy":                     "#ff0000",
    "Very Unhealthy":                "#8f3f97",
    "Hazardous":                     "#7e0023",
}

# /tmp cache — persists across warm invocations within the same execution environment
_CACHE_FILE = "/tmp/aqi_geojson_cache.json"
CACHE_TTL_SECONDS = int(os.environ.get("CACHE_TTL_SECONDS", "3600"))  # default 1 h


def _load_cache() -> dict | None:
    """Return cached GeoJSON if it exists and is less than CACHE_TTL_SECONDS old."""
    try:
        with open(_CACHE_FILE) as f:
            cached = json.load(f)
        if time.time() - cached.get("_cached_at", 0) < CACHE_TTL_SECONDS:
            return cached["payload"]
    except (FileNotFoundError, KeyError, json.JSONDecodeError):
        pass
    return None


def _save_cache(payload: dict) -> None:
    try:
        with open(_CACHE_FILE, "w") as f:
            json.dump({"_cached_at": time.time(), "payload": payload}, f)
    except OSError:
        pass  # non-fatal — next invocation will re-query Athena


def handler(event, context):
    database  = os.environ.get("ATHENA_DATABASE",  "openaq_mart")
    workgroup = os.environ.get("ATHENA_WORKGROUP", "openaq_workgroup")
    bucket    = os.environ.get("S3_BUCKET_NAME",   "")

    # Serve from /tmp cache when available (warm invocation, data < 1 h old)
    cached = _load_cache()
    if cached is not None:
        return {
            "statusCode": 200,
            "headers": {
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*",
                "Cache-Control": "max-age=3600",
                "X-Cache": "HIT",
            },
            "body": json.dumps(cached),
        }

    try:
        client = boto3.client("athena", region_name=os.environ.get("AWS_REGION", "ap-southeast-1"))
        cfg    = AthenaConfig(database=database, workgroup=workgroup)
        rows   = run_query(client, QUERY, cfg, max_wait=60)
    except Exception as exc:
        return {
            "statusCode": 500,
            "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
            "body": json.dumps({"error": str(exc)}),
        }

    features = []
    for row in rows:
        try:
            lat = float(row["station_lat"])
            lon = float(row["station_lon"])
            aqi = int(row["composite_aqi"]) if row["composite_aqi"] else None
        except (ValueError, KeyError):
            continue

        category = row.get("health_category", "")
        raw_cig = row.get("cigarette_equivalent", "")
        cig = round(float(raw_cig), 1) if raw_cig else None

        raw_pm25 = row.get("pm25_avg", "")
        pm25 = round(float(raw_pm25), 1) if raw_pm25 else None

        features.append({
            "type": "Feature",
            "geometry": {"type": "Point", "coordinates": [lon, lat]},
            "properties": {
                "location_id": int(row["location_id"]),
                "location_name": row["location_name"],
                "city": row["city"],
                "composite_aqi": aqi,
                "health_category": category,
                "dominant_pollutant": row.get("dominant_pollutant", ""),
                "sensor_type": row.get("sensor_type", ""),
                "pm25_avg": pm25,
                "cigarette_equivalent": cig,
                "measurement_date": row.get("measurement_date", ""),
                "colour": AQI_COLOURS.get(category, "#cccccc"),
            },
        })

    updated_at = max((r["measurement_date"] for r in rows), default="")
    geojson = {"type": "FeatureCollection", "updated_at": updated_at, "features": features}

    _save_cache(geojson)

    return {
        "statusCode": 200,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Cache-Control": "max-age=3600",
            "X-Cache": "MISS",
        },
        "body": json.dumps(geojson),
    }

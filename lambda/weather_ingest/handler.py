"""
weather_ingest/handler.py — Daily weather fetch from Open-Meteo Historical Archive.

Fetches previous day's hourly ERA5 reanalysis data for all 21 Vietnamese
monitoring station coordinates and writes NDJSON to S3.

S3 output path: raw/weather/{location_id}/{yyyy}/{MM}/{dd}/weather.ndjson
Schema per row:
    location_id, date, hour_utc, temperature_2m, rh_2m, wind_speed,
    wind_dir, precipitation_mm, surface_pressure_hpa, boundary_layer_height_m

Triggered daily at 02:00 UTC by EventBridge Scheduler.
Backfill: set BACKFILL_DAYS=N env var to fetch N consecutive days ending yesterday.

ADR-010: Open-Meteo selected over NOAA ISD / ERA5-CDS — see docs/architecture-decision-record.md.
"""

import json
import logging
import os
from datetime import date, timedelta

import boto3
import requests

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

S3_BUCKET = os.environ["S3_BUCKET_NAME"]

# All 21 Vietnamese monitoring stations (lat/lon from vn_stations seed).
# Coordinates drive the Open-Meteo grid-cell selection (0.25° ERA5 resolution).
STATIONS = [
    # Hanoi — reference stations
    {"location_id": 7441,    "lat": 21.021939, "lon": 105.818806},
    {"location_id": 2539,    "lat": 21.021770, "lon": 105.819002},
    {"location_id": 1285357, "lat": 21.047800, "lon": 105.800000},
    {"location_id": 2161290, "lat": 21.002400, "lon": 105.718100},
    {"location_id": 2161291, "lat": 21.039800, "lon": 105.765200},
    {"location_id": 2161292, "lat": 21.015200, "lon": 105.799900},
    {"location_id": 2161316, "lat": 21.019700, "lon": 105.814700},
    {"location_id": 2161317, "lat": 21.228700, "lon": 105.758300},
    {"location_id": 2161318, "lat": 21.063900, "lon": 105.833800},
    {"location_id": 2161319, "lat": 20.733900, "lon": 105.770300},
    {"location_id": 2161320, "lat": 21.147600, "lon": 105.915900},
    {"location_id": 2161321, "lat": 20.972000, "lon": 105.785600},
    {"location_id": 2161323, "lat": 20.899400, "lon": 105.577300},
    {"location_id": 4946811, "lat": 21.049100, "lon": 105.883100},
    {"location_id": 4946812, "lat": 21.003100, "lon": 105.794700},
    {"location_id": 4946813, "lat": 21.005200, "lon": 105.841800},
    # Hanoi — low-cost sensor
    {"location_id": 6123215, "lat": 20.993300, "lon": 105.944100},
    # Ho Chi Minh City — reference stations
    {"location_id": 7440,    "lat": 10.782773, "lon": 106.700035},
    {"location_id": 2446,    "lat": 10.783041, "lon": 106.700722},
    # Ho Chi Minh City — low-cost sensors
    {"location_id": 6068138, "lat": 10.774491, "lon": 106.661026},
    {"location_id": 6273386, "lat": 10.761968, "lon": 106.682582},
]

_ARCHIVE_URL = "https://archive-api.open-meteo.com/v1/archive"

_HOURLY_VARS = ",".join([
    "temperature_2m",
    "relative_humidity_2m",
    "wind_speed_10m",
    "wind_direction_10m",
    "precipitation",
    "surface_pressure",
    "boundary_layer_height",
])


def _fetch_weather_range(lat: float, lon: float, start_date: str, end_date: str) -> dict:
    """Fetch hourly ERA5 weather from Open-Meteo for a single station over a date range.

    One HTTP request covers all requested dates — avoids N×stations requests when
    backfill_days > 1 (e.g. backfill_days=365 was 7,665 requests; now it is 21).
    """
    resp = requests.get(
        _ARCHIVE_URL,
        params={
            "latitude":   lat,
            "longitude":  lon,
            "start_date": start_date,
            "end_date":   end_date,
            "hourly":     _HOURLY_VARS,
            "timezone":   "UTC",
        },
        timeout=60,
    )
    resp.raise_for_status()
    return resp.json()


def _rows_for_date(location_id: int, target_date: date, hourly: dict, indices: list[int]) -> list[str]:
    """Serialise the hourly rows belonging to target_date as NDJSON lines."""
    date_str = target_date.isoformat()
    rows = []
    for i in indices:
        time_str = hourly["time"][i]          # "2024-01-01T00:00"
        hour_utc = int(time_str[11:13])       # faster than split
        row = {
            "location_id":             location_id,
            "date":                    date_str,
            "hour_utc":                hour_utc,
            "temperature_2m":          hourly["temperature_2m"][i],
            "rh_2m":                   hourly["relative_humidity_2m"][i],
            "wind_speed":              hourly["wind_speed_10m"][i],
            "wind_dir":                hourly["wind_direction_10m"][i],
            "precipitation_mm":        hourly["precipitation"][i],
            "surface_pressure_hpa":    hourly["surface_pressure"][i],
            "boundary_layer_height_m": hourly["boundary_layer_height"][i],
        }
        rows.append(json.dumps(row, separators=(",", ":")))
    return rows


def _s3_key(location_id: int, target_date: date) -> str:
    return (
        f"raw/weather/{location_id}/"
        f"{target_date.year}/{target_date.month:02d}/{target_date.day:02d}/"
        "weather.ndjson"
    )


def handler(event, context):
    """Lambda entry point.

    event keys (all optional):
        backfill_days (int): override BACKFILL_DAYS env var for this invocation.
    """
    s3 = boto3.client("s3")

    backfill_days = int(
        event.get("backfill_days") or os.environ.get("BACKFILL_DAYS", "1")
    )

    today = date.today()
    # Fetch from yesterday back N days (Open-Meteo ERA5 lag ~5 days)
    target_dates = sorted(
        [today - timedelta(days=d) for d in range(1, backfill_days + 1)]
    )
    start_str = target_dates[0].isoformat()
    end_str   = target_dates[-1].isoformat()

    total_written = 0
    error_count   = 0

    for station in STATIONS:
        location_id = station["location_id"]
        try:
            # One HTTP request covers the full date range for this station.
            data   = _fetch_weather_range(station["lat"], station["lon"], start_str, end_str)
            hourly = data["hourly"]

            # Build a mapping date_str → [row indices] so we can write one S3
            # object per date without a second pass over the full hourly array.
            date_index: dict[str, list[int]] = {}
            for i, time_str in enumerate(hourly["time"]):
                d_str = time_str[:10]   # "YYYY-MM-DD"
                date_index.setdefault(d_str, []).append(i)

            for target_date in target_dates:
                d_str   = target_date.isoformat()
                indices = date_index.get(d_str, [])
                if not indices:
                    logger.warning("No hourly data for station %s on %s", location_id, d_str)
                    continue
                rows   = _rows_for_date(location_id, target_date, hourly, indices)
                ndjson = "\n".join(rows)
                key    = _s3_key(location_id, target_date)
                s3.put_object(
                    Bucket=S3_BUCKET,
                    Key=key,
                    Body=ndjson.encode("utf-8"),
                    ContentType="application/x-ndjson",
                )
                logger.info("Wrote s3://%s/%s", S3_BUCKET, key)
                total_written += 1

        except Exception as exc:
            logger.error("Failed location_id=%s range=%s..%s: %s",
                         location_id, start_str, end_str, exc)
            error_count += 1

    logger.info(
        "Completed: %d written, %d errors (backfill_days=%d, stations=%d, requests=%d)",
        total_written, error_count, backfill_days, len(STATIONS), len(STATIONS),
    )
    return {"total_written": total_written, "errors": error_count}

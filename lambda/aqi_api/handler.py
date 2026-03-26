"""
aqi_api — Lambda-backed API returning latest composite AQI per station as GeoJSON.

Queries mart_daily_aqi via Athena for the most recent date with data,
then returns a GeoJSON FeatureCollection for the Leaflet map.

Environment variables:
  S3_BUCKET_NAME      — project S3 bucket for Athena staging output
  ATHENA_DATABASE     — Glue database (default: openaq_mart)
  ATHENA_WORKGROUP    — Athena workgroup (default: openaq_workgroup)

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
          "measurement_date": "2026-03-26"
        }
      }
    ]
  }
"""

import json
import os
import time

import boto3

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
    CAST(a.measurement_date AS VARCHAR) AS measurement_date
FROM openaq_mart.mart_daily_aqi a
INNER JOIN (
    SELECT location_id, MAX(measurement_date) AS latest_date
    FROM openaq_mart.mart_daily_aqi
    GROUP BY location_id
) latest
    ON a.location_id = latest.location_id
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


def _run_athena_query(sql: str, database: str, workgroup: str, output_location: str) -> list[dict]:
    client = boto3.client("athena", region_name=os.environ.get("AWS_REGION", "ap-southeast-1"))

    response = client.start_query_execution(
        QueryString=sql,
        QueryExecutionContext={"Database": database},
        WorkGroup=workgroup,
        ResultConfiguration={"OutputLocation": output_location},
    )
    qid = response["QueryExecutionId"]

    for _ in range(30):
        state = client.get_query_execution(QueryExecutionId=qid)["QueryExecution"]["Status"]["State"]
        if state == "SUCCEEDED":
            break
        if state in ("FAILED", "CANCELLED"):
            reason = client.get_query_execution(QueryExecutionId=qid)["QueryExecution"]["Status"].get(
                "StateChangeReason", "unknown"
            )
            raise RuntimeError(f"Athena query {state}: {reason}")
        time.sleep(2)
    else:
        raise TimeoutError("Athena query did not complete within 60 seconds")

    paginator = client.get_paginator("get_query_results")
    rows = []
    headers = None
    for page in paginator.paginate(QueryExecutionId=qid):
        for row in page["ResultSet"]["Rows"]:
            values = [d.get("VarCharValue", "") for d in row["Data"]]
            if headers is None:
                headers = values
            else:
                rows.append(dict(zip(headers, values)))
    return rows


def handler(event, context):
    bucket = os.environ["S3_BUCKET_NAME"]
    database = os.environ.get("ATHENA_DATABASE", "openaq_mart")
    workgroup = os.environ.get("ATHENA_WORKGROUP", "openaq_workgroup")
    output = f"s3://{bucket}/aqi-api-results/"

    try:
        rows = _run_athena_query(QUERY, database, workgroup, output)
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
                "measurement_date": row.get("measurement_date", ""),
                "colour": AQI_COLOURS.get(category, "#cccccc"),
            },
        })

    updated_at = rows[0]["measurement_date"] if rows else ""
    geojson = {"type": "FeatureCollection", "updated_at": updated_at, "features": features}

    return {
        "statusCode": 200,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Cache-Control": "max-age=3600",
        },
        "body": json.dumps(geojson),
    }

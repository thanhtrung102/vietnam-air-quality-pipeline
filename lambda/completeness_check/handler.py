"""
openaq_completeness_check — station coverage monitor (Gap 6: IoT Lens).

Triggered hourly by EventBridge Scheduler. Queries mart_daily_aqi via Athena
to count distinct active stations for the current date. Emits a CloudWatch
custom metric MissingStations (namespace: OpenAQ/Pipeline). Publishes an SNS
alert if the count falls below the configured threshold for this invocation.

Note: the CloudWatch alarm (missing_stations in lambda.tf) fires only after
2 consecutive breaches — so a single transient failure does not page anyone.

Environment variables:
    S3_BUCKET_NAME      Project S3 bucket (Athena result output)
    ATHENA_DATABASE     Glue database (openaq_mart)
    ATHENA_WORKGROUP    Athena workgroup (openaq_workgroup)
    EXPECTED_STATIONS   Total stations expected (default 21)
    ALERT_THRESHOLD     Minimum acceptable count (default 18 = 85%)
    SNS_ALERT_TOPIC_ARN SNS topic ARN for immediate alerts
"""

import os
import sys
from datetime import date, timezone, datetime

import boto3
from botocore.exceptions import ClientError

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "shared"))
from athena_utils import AthenaConfig, run_query  # noqa: E402

EXPECTED_STATIONS = int(os.environ.get("EXPECTED_STATIONS", "21"))
ALERT_THRESHOLD   = int(os.environ.get("ALERT_THRESHOLD",   "18"))
MAX_WAIT          = 90     # seconds; leaves buffer before 120s Lambda timeout


def _emit_metric(cw, missing_count: int) -> None:
    """Emit MissingStations metric to CloudWatch."""
    cw.put_metric_data(
        Namespace="OpenAQ/Pipeline",
        MetricData=[{
            "MetricName": "MissingStations",
            "Value": missing_count,
            "Unit": "Count",
        }],
    )


def handler(event, context):
    bucket        = os.environ["S3_BUCKET_NAME"]
    database      = os.environ.get("ATHENA_DATABASE",   "openaq_mart")
    workgroup     = os.environ.get("ATHENA_WORKGROUP",  "openaq_workgroup")
    sns_topic_arn = os.environ.get("SNS_ALERT_TOPIC_ARN", "")

    output_location = f"s3://{bucket}/athena-results/"

    athena = boto3.client("athena")
    cw     = boto3.client("cloudwatch")
    sns    = boto3.client("sns") if sns_topic_arn else None

    # Use the most recent date present in the mart rather than today.
    # OpenAQ's public S3 archive publishes with a multi-day (sometimes multi-month)
    # lag, so checking "today" always returns 0 until the archive catches up.
    # This query finds the latest date and checks coverage for that date instead.
    query = """
        SELECT
            CAST(measurement_date AS VARCHAR) AS check_date,
            COUNT(DISTINCT location_id)       AS station_count
        FROM mart_daily_aqi
        WHERE measurement_date = (SELECT MAX(measurement_date) FROM mart_daily_aqi)
        GROUP BY measurement_date
    """

    cfg = AthenaConfig(database=database, workgroup=workgroup, output_location=output_location)

    try:
        rows = run_query(athena, query, cfg, max_wait=MAX_WAIT)

        if not rows:
            check_date, active_count = date.today().isoformat(), 0
        else:
            check_date   = rows[0]["check_date"]
            active_count = int(rows[0]["station_count"])
        missing_count = max(0, EXPECTED_STATIONS - active_count)

        data_age_days = (datetime.now(timezone.utc).date() -
                         datetime.fromisoformat(check_date).date()).days

        print(f"Station completeness: {active_count}/{EXPECTED_STATIONS} "
              f"({missing_count} missing) for {check_date} (data age: {data_age_days}d)")

        _emit_metric(cw, missing_count)

        # Suppress SNS alert when the archive itself is stale (>7 days old).
        # A stale archive is an upstream data availability issue, not a pipeline
        # failure — alerting every hour would be noise. The CloudWatch metric is
        # still emitted so the dashboard reflects the true state.
        is_archive_stale = data_age_days > 7
        if is_archive_stale:
            print(f"Archive data is {data_age_days} days old — suppressing SNS alert (upstream lag)")

        if active_count < ALERT_THRESHOLD and not is_archive_stale and sns_topic_arn and sns:
            msg = (
                f"OpenAQ pipeline alert: only {active_count}/{EXPECTED_STATIONS} stations "
                f"reported data for {check_date} ({missing_count} missing). "
                f"Threshold: {ALERT_THRESHOLD}. Check Lambda logs and OpenAQ API status."
            )
            sns.publish(
                TopicArn=sns_topic_arn,
                Subject=f"[OpenAQ] Station completeness below threshold ({active_count}/{EXPECTED_STATIONS})",
                Message=msg,
            )
            print(f"SNS alert published: {active_count} < {ALERT_THRESHOLD}")

        return {
            "date":           check_date,
            "data_age_days":  data_age_days,
            "is_archive_stale":  is_archive_stale,
            "active":         active_count,
            "missing":        missing_count,
            "expected":       EXPECTED_STATIONS,
            "alert_threshold": ALERT_THRESHOLD,
        }

    except (RuntimeError, TimeoutError) as exc:
        print(f"ERROR: Athena error: {exc}")
        return {"error": str(exc)}
    except ClientError as exc:
        print(f"ERROR: AWS client error: {exc}")
        return {"error": str(exc)}

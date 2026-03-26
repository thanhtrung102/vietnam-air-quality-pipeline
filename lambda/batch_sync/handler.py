import os
import subprocess
import sys
from datetime import datetime

STATION_IDS = [
    7441, 2539, 1285357,
    2161290, 2161291, 2161292, 2161316, 2161317, 2161318,
    2161319, 2161320, 2161321, 2161323,
    4946811, 4946812, 4946813, 6123215,
    7440, 2446, 6068138, 6273386,
]

def handler(event, context):
    bucket = os.environ["S3_BUCKET_NAME"]
    now = datetime.utcnow()
    year = str(now.year)
    month = str(now.month).zfill(2)
    success = 0
    failed = []

    for station_id in STATION_IDS:
        src = f"s3://openaq-data-archive/records/csv.gz/locationid={station_id}/year={year}/month={month}/"
        dst = f"s3://{bucket}/raw/batch/locationid={station_id}/year={year}/month={month}/"
        result = subprocess.run(
            ["aws", "s3", "sync", src, dst,
             "--request-payer", "requester",
             "--only-show-errors"],
            capture_output=True, text=True
        )
        if result.returncode == 0:
            success += 1
        else:
            failed.append(str(station_id))
            print(f"WARN sync failed for {station_id}: {result.stderr}", file=sys.stderr)

    print(f"Batch sync complete: success={success} failed={len(failed)}")
    if failed:
        print(f"Failed stations: {failed}")
    return {"success": success, "failed": failed}

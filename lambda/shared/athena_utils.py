"""
Shared Athena query helper — used by aqi_api, completeness_check, and forecast_generate.

Packaging note: build.sh copies this file to the root of each Lambda package so
that `from athena_utils import ...` resolves in the Lambda runtime.  The
sys.path.insert in each handler is only needed for local development.
"""

import time
from dataclasses import dataclass, field


@dataclass
class AthenaConfig:
    """All config values that travel together for an Athena query."""
    database:        str
    workgroup:       str
    output_location: str = ""   # if empty, workgroup's default location is used


def run_query(
    client,
    sql: str,
    cfg: AthenaConfig,
    *,
    poll_interval: int = 2,
    max_wait:      int = 300,
) -> list[dict]:
    """
    Submit *sql* to Athena, poll until completion, and return rows as list[dict].

    Raises:
        RuntimeError  — query FAILED or CANCELLED (message includes StateChangeReason)
        TimeoutError  — query did not finish within *max_wait* seconds
    """
    kwargs = {
        "QueryString":            sql,
        "QueryExecutionContext":  {"Database": cfg.database},
        "WorkGroup":              cfg.workgroup,
    }
    if cfg.output_location:
        kwargs["ResultConfiguration"] = {"OutputLocation": cfg.output_location}

    qid = client.start_query_execution(**kwargs)["QueryExecutionId"]

    deadline = time.time() + max_wait
    while time.time() < deadline:
        execution = client.get_query_execution(QueryExecutionId=qid)["QueryExecution"]
        state = execution["Status"]["State"]
        if state == "SUCCEEDED":
            break
        if state in ("FAILED", "CANCELLED"):
            reason = execution["Status"].get("StateChangeReason", "unknown")
            raise RuntimeError(f"Athena query {state}: {reason}")
        time.sleep(poll_interval)
    else:
        raise TimeoutError(f"Athena query {qid} did not complete within {max_wait}s")

    paginator = client.get_paginator("get_query_results")
    rows: list[dict] = []
    headers: list[str] | None = None
    for page in paginator.paginate(QueryExecutionId=qid):
        for row in page["ResultSet"]["Rows"]:
            values = [d.get("VarCharValue", "") for d in row["Data"]]
            if headers is None:
                headers = values
            else:
                rows.append(dict(zip(headers, values)))
    return rows

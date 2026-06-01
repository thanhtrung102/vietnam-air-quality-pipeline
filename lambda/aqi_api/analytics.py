"""
analytics — read-only analytical datasets for the dashboard "Analytics" tab.

A QuickSight alternative: each dataset is a small, partition-free aggregate mart
queried via Athena and returned as JSON. Consumed by dashboard/index.html
(Chart.js) over the API Gateway routes GET /analytics/{dataset}.

Datasets (3-sheet MVP, PM2.5, outlier station excluded where per-station):
  health      → mart_health_summary    (city × year)         — Health Scorecard
  seasonal    → mart_monthly_profile +  mart_diurnal_profile  — Seasonal & Weather Drivers
  compliance  → mart_exceedance_stats   (city × year × month) — Compliance & Trajectory

All marts here are tiny (city/month grain), so scans are a few KB. Results are
cached by the caller (handler.py) in /tmp, keyed per dataset + UTC day.
"""

from athena_utils import run_query  # provided at package root by build.sh

# city × year — already aggregated in the mart
_HEALTH = """
SELECT city, year, who_compliance_pct, avg_pm25, avg_cigarette_equivalent,
       good_days, moderate_days, usg_days, unhealthy_days,
       very_unhealthy_days, hazardous_days, risk_label
FROM openaq_mart.mart_health_summary
ORDER BY city, year
"""

# per-station marts → collapse to one city-level PM2.5 average (non-outlier)
_SEASONAL_MONTHLY = """
SELECT city, month_of_year, ROUND(AVG(avg_value), 1) AS avg_pm25
FROM openaq_mart.mart_monthly_profile
WHERE parameter = 'pm25' AND is_outlier_station = 0
GROUP BY city, month_of_year
ORDER BY city, month_of_year
"""

_SEASONAL_DIURNAL = """
SELECT city, hour_of_day, day_type, ROUND(AVG(avg_value), 1) AS avg_pm25
FROM openaq_mart.mart_diurnal_profile
WHERE parameter = 'pm25' AND is_outlier_station = 0
GROUP BY city, hour_of_day, day_type
ORDER BY city, day_type, hour_of_day
"""

# city × year × month — already aggregated
_COMPLIANCE = """
SELECT city, year, month_of_year, who_exceedance_rate, qcvn_exceedance_rate,
       p95_pm25, avg_pm25
FROM openaq_mart.mart_exceedance_stats
WHERE parameter = 'pm25'
ORDER BY city, year, month_of_year
"""

# numeric coercion per column so the JSON is typed, not all-strings
_INT = {"year", "month_of_year", "hour_of_day", "good_days", "moderate_days",
        "usg_days", "unhealthy_days", "very_unhealthy_days", "hazardous_days"}


def _typed(rows):
    out = []
    for r in rows:
        rec = {}
        for k, v in r.items():
            if v is None or v == "":
                rec[k] = None
            elif k in _INT:
                try:
                    rec[k] = int(float(v))
                except (ValueError, TypeError):
                    rec[k] = None
            else:
                try:
                    rec[k] = float(v)
                except (ValueError, TypeError):
                    rec[k] = v  # keep strings (city, day_type, risk_label)
        out.append(rec)
    return out


def get_dataset(client, cfg, dataset, max_wait=60):
    """Return the JSON-able payload for an analytics dataset, or None if unknown."""
    if dataset == "health":
        return {"rows": _typed(run_query(client, _HEALTH, cfg, max_wait=max_wait))}
    if dataset == "seasonal":
        return {
            "monthly": _typed(run_query(client, _SEASONAL_MONTHLY, cfg, max_wait=max_wait)),
            "diurnal": _typed(run_query(client, _SEASONAL_DIURNAL, cfg, max_wait=max_wait)),
        }
    if dataset == "compliance":
        return {"monthly": _typed(run_query(client, _COMPLIANCE, cfg, max_wait=max_wait))}
    return None

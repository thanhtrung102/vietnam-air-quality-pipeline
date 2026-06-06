"""Generate deterministic demo analytics JSON for the offline dashboard (no AWS/Athena).

Produces the four payloads dashboard/index.html fetches from /api/analytics/{dataset}, matching the
exact shapes that lambda/aqi_api/analytics.py returns from the marts. Pure-deterministic (formula
based on city/month, no RNG) so the dashboard renders identically every run.
"""
import json
import math
from pathlib import Path

OUT = Path(__file__).parent / "demo_analytics"
OUT.mkdir(exist_ok=True)

# (city, base PM2.5, winter amplitude) — northern cities run dirtier, stronger winter peak
CITIES = [
    ("Hanoi", 42, 22), ("Ho Chi Minh City", 28, 8), ("Da Nang", 22, 6),
    ("Hai Phong", 38, 18), ("Can Tho", 24, 7),
]
YEARS = [2023, 2024, 2025]


def pm25(base, amp, month):
    # winter (Dec–Feb) peak via cosine centred on January
    return round(base + amp * math.cos((month - 1) / 12 * 2 * math.pi), 1)


def risk(p):
    return "Extreme" if p >= 55 else "High" if p >= 40 else "Moderate" if p >= 25 else "Low"


# health: city × year
health = []
for city, base, amp in CITIES:
    for y in YEARS:
        avg = round(base - (y - 2023) * 1.5, 1)  # gentle improving trend
        total = 365
        haz = max(0, int((avg - 35) * 2)); vu = max(0, int((avg - 25) * 3))
        unh = int(avg * 1.5); usg = int(avg * 2); mod = int(avg * 2.5)
        good = max(0, total - haz - vu - unh - usg - mod)
        health.append({
            "city": city, "year": y,
            "who_compliance_pct": round(max(0, 100 - avg * 1.6), 1),
            "avg_pm25": avg, "avg_cigarette_equivalent": round(avg / 22, 2),
            "good_days": good, "moderate_days": mod, "usg_days": usg,
            "unhealthy_days": unh, "very_unhealthy_days": vu, "hazardous_days": haz,
            "risk_label": risk(avg),
        })

# seasonal: monthly (city × month) + diurnal (city × hour × day_type)
monthly = [{"city": c, "month_of_year": m, "avg_pm25": pm25(base, amp, m)}
           for c, base, amp in CITIES for m in range(1, 13)]
diurnal = []
for c, base, amp in CITIES:
    for dt in ("weekday", "weekend"):
        for h in range(24):
            # rush-hour bumps on weekdays
            bump = 12 if (dt == "weekday" and h in (7, 8, 18, 19)) else 0
            diurnal.append({"city": c, "hour_of_day": h, "day_type": dt,
                            "avg_pm25": round(base + bump + 5 * math.sin(h / 24 * 2 * math.pi), 1)})

# compliance: city × year × month
compliance = []
for c, base, amp in CITIES:
    for y in YEARS:
        for m in range(1, 13):
            p = pm25(base - (y - 2023) * 1.5, amp, m)
            compliance.append({
                "city": c, "year": y, "month_of_year": m,
                "who_exceedance_rate": round(min(1.0, p / 15), 3),
                "qcvn_exceedance_rate": round(min(1.0, p / 50), 3),
                "p95_pm25": round(p * 1.6, 1), "avg_pm25": p,
            })

# forecast: 7-day SARIMA per a couple stations
forecast = []
for loc, c, base in [("Hanoi-US-Embassy", "Hanoi", 44), ("HCMC-Consulate", "Ho Chi Minh City", 29)]:
    for d in range(1, 8):
        fp = round(base + 6 * math.cos(d / 7 * math.pi), 1)
        aqi = int(fp * 4.0)
        forecast.append({
            "location_name": loc, "city": c, "forecast_date": f"2026-01-0{d}",
            "forecast_pm25": fp, "forecast_aqi": aqi,
            "forecast_aqi_category": "Unhealthy" if aqi > 150 else "USG" if aqi > 100 else "Moderate",
            "ci_lower_95": round(fp * 0.8, 1), "ci_upper_95": round(fp * 1.2, 1),
            "holdout_rmse": 6.4,
        })

(OUT / "health.json").write_text(json.dumps({"rows": health}), encoding="utf-8")
(OUT / "seasonal.json").write_text(json.dumps({"monthly": monthly, "diurnal": diurnal}), encoding="utf-8")
(OUT / "compliance.json").write_text(json.dumps({"monthly": compliance}), encoding="utf-8")
(OUT / "forecast.json").write_text(json.dumps({"rows": forecast}), encoding="utf-8")
print("wrote demo_analytics:", [p.name for p in OUT.glob("*.json")],
      f"(health={len(health)}, monthly={len(monthly)}, diurnal={len(diurnal)}, compliance={len(compliance)}, forecast={len(forecast)})")

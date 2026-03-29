"""
generate_leaflet_render.py — Vietnam Air Quality Pipeline
Renders a static mock-up of the Leaflet station map dashboard.

Replicates:  dashboard/index.html  (CartoDB Dark Matter style)
  - Dark background map of Vietnam (approximate bounding polygon)
  - 21 station circle markers coloured by AQI category
  - AQI legend (bottom-right)
  - Station popup data panel (bottom-left inset)

Run:  python docs/generate_leaflet_render.py
"""

from pathlib import Path
import random, math
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import matplotlib.patheffects as pe
import numpy as np

random.seed(7)
np.random.seed(7)

OUT = Path(__file__).parent / "leaflet_map.png"

# ── AQI colours (matching dashboard/index.html) ───────────────────────────────
AQI_COLOURS = {
    "Good":                            "#00C851",
    "Moderate":                        "#FFD700",
    "Unhealthy for Sensitive Groups":  "#FF7E00",
    "Unhealthy":                       "#FF4444",
    "Very Unhealthy":                  "#8F3F97",
    "Hazardous":                       "#7E0023",
}

THRESHOLDS = [
    ("WHO Annual AQG",  5,  "#4ade80"),
    ("WHO 24h AQG",    15,  "#60a5fa"),
    ("QCVN 05:2023",   25,  "#fb923c"),
    ("WHO IT-1",       35,  "#f87171"),
]

# ── Station data (transform/seeds/vn_stations.csv + simulated AQI) ────────────
# Simulated AQI values reflect: Hanoi winter season avg ~106, HCMC ~57
# Each station gets a plausible 7-day avg AQI value with inter-station variance

def _rand_aqi(base, sigma=18):
    return max(10, int(np.random.normal(base, sigma)))

def pm25_to_cat_full(pm25):
    if pm25 <=  9.0: return "Good"
    if pm25 <= 35.4: return "Moderate"
    if pm25 <= 55.4: return "Unhealthy for Sensitive Groups"
    if pm25 <= 125.4: return "Unhealthy"
    if pm25 <= 225.4: return "Very Unhealthy"
    return "Hazardous"

def aqi_to_cat(aqi):
    if aqi <=  50: return "Good"
    if aqi <= 100: return "Moderate"
    if aqi <= 150: return "Unhealthy for Sensitive Groups"
    if aqi <= 200: return "Unhealthy"
    if aqi <= 300: return "Very Unhealthy"
    return "Hazardous"

STATIONS = [
    # name, lat, lon, sensor_type, base_aqi
    ("US Embassy Hanoi",             21.0219, 105.8188, "reference",  108),
    ("US Diplomatic Post Hanoi",     21.0218, 105.8190, "reference",  106),
    ("SPARTAN – Vietnam Acad. Sci.", 21.0478, 105.8000, "reference",  112),
    ("An Khánh",                     21.0024, 105.7181, "reference",   98),
    ("Cầu Diễn",                     21.0398, 105.7652, "reference",  102),
    ("Số 46 Lưu Quang Vũ",           21.0152, 105.7999, "reference",  118),
    ("Thành Công",                   21.0197, 105.8147, "reference",  104),
    ("Thanh Xuân – Sóc Sơn",         21.2287, 105.7583, "reference",   95),
    ("Tứ Liên",                      21.0639, 105.8338, "reference",  110),
    ("Vân Đình",                     20.7339, 105.7703, "reference",   88),
    ("Vân Hà",                       21.1476, 105.9159, "reference",   92),
    ("Văn Quán",                     20.9720, 105.7856, "reference",  100),
    ("Xuân Mai",                     20.8994, 105.5773, "reference",   85),
    ("556 Nguyễn Văn Cừ",            21.0491, 105.8831, "reference",  116),
    ("Nhân Chính Park",              21.0031, 105.7947, "reference",  114),
    ("Số 1 Giải Phóng",              21.0052, 105.8418, "reference",  120),
    ("OceanPark",                    20.9933, 105.9441, "low_cost",    75),
    ("US Diplomatic HCMC",           10.7828, 106.7000, "reference",   62),
    ("US Diplomatic HCMC (prev.)",   10.7830, 106.7007, "reference",   58),
    ("Care Centre",                  10.7745, 106.6610, "low_cost",    55),
    ("VNUHCMUS Campus 1",            10.7620, 106.6826, "low_cost",   148),
]

STATION_DATA = []
for name, lat, lon, stype, base in STATIONS:
    aqi = _rand_aqi(base, 15)
    cat = aqi_to_cat(aqi)
    pm25 = round(max(2, np.random.normal(base * 0.38, 8)), 1)  # rough PM2.5 from AQI
    cigs = round(pm25 / 22.0, 1)
    STATION_DATA.append({
        "name": name, "lat": lat, "lon": lon,
        "sensor_type": stype, "aqi": aqi,
        "category": cat, "pm25": pm25, "cigs": cigs,
        "colour": AQI_COLOURS[cat],
    })

# ── Vietnam approximate boundary polygon (simplified) ─────────────────────────
# A rough clockwise polygon covering Vietnam's coastline/border
VN_POLY = [
    # Northern border (China)
    (23.37, 102.14), (22.97, 103.00), (22.50, 103.98), (22.79, 104.79),
    (23.32, 105.37), (23.35, 106.70),
    # East coast (Gulf of Tonkin → South China Sea)
    (21.55, 107.98), (20.98, 107.28), (20.42, 106.72), (19.98, 106.00),
    (19.40, 105.58), (18.38, 105.90), (17.52, 106.54), (16.50, 107.85),
    (15.97, 108.27), (15.12, 108.87), (13.76, 109.22), (12.25, 109.19),
    (11.26, 108.87), (10.42, 107.42), (10.27, 106.80),
    # Southern tip
    (10.16, 104.84), (10.43, 104.06),
    # West coast / Cambodia border
    (10.86, 104.44), (11.00, 103.99),
    (11.56, 104.68), (11.98, 105.09), (12.52, 107.49),
    (13.00, 107.63), (14.36, 107.79), (15.13, 107.93),
    (14.42, 107.24), (13.93, 107.55),
    # Laos / NW border
    (15.47, 106.52), (16.10, 106.02), (17.24, 105.68),
    (18.34, 105.34), (19.47, 103.91), (20.20, 102.80),
    (20.88, 102.15), (21.84, 102.27), (22.51, 102.51),
    (23.37, 102.14),
]

# ════════════════════════════════════════════════════════════════════════════════

fig, ax = plt.subplots(figsize=(12, 18), facecolor="#0F172A")
ax.set_facecolor("#0F172A")

# Map extent — show full Vietnam + margins
LAT_MIN, LAT_MAX = 8.5, 24.0
LON_MIN, LON_MAX = 101.5, 110.5
ax.set_xlim(LON_MIN, LON_MAX)
ax.set_ylim(LAT_MIN, LAT_MAX)

# ── Subtle graticule ───────────────────────────────────────────────────────────
for lat in np.arange(9, 24, 2):
    ax.axhline(lat, color="#1E293B", lw=0.6, zorder=0)
for lon in np.arange(102, 111, 2):
    ax.axvline(lon, color="#1E293B", lw=0.6, zorder=0)

# ── Vietnam outline ────────────────────────────────────────────────────────────
poly_lons = [p[1] for p in VN_POLY]
poly_lats = [p[0] for p in VN_POLY]
ax.fill(poly_lons, poly_lats, color="#1E3A5F", alpha=0.55, zorder=1)
ax.plot(poly_lons + [poly_lons[0]], poly_lats + [poly_lats[0]],
        color="#334155", lw=0.9, zorder=2)

# Neighbouring country labels (faint)
for lbl, lat, lon in [("CHINA", 23.5, 104.5), ("LAOS", 19.5, 102.8),
                       ("CAMBODIA", 12.0, 105.0), ("GULF\nOF TONKIN", 19.5, 107.8),
                       ("SOUTH\nCHINA SEA", 12.5, 109.0)]:
    ax.text(lon, lat, lbl, color="#334155", fontsize=8, ha="center", va="center",
            fontweight="bold", fontstyle="italic", zorder=1)

# ── City region labels ─────────────────────────────────────────────────────────
for city, lat, lon in [("HANOI", 21.35, 105.2), ("HO CHI MINH CITY", 10.35, 106.4)]:
    ax.text(lon, lat, city, color="#94A3B8", fontsize=9.5, ha="center",
            fontweight="bold", zorder=6,
            path_effects=[pe.withStroke(linewidth=3, foreground="#0F172A")])

# ── Station markers ────────────────────────────────────────────────────────────
def aqi_radius(aqi):
    if aqi >= 201: return 0.32
    if aqi >= 151: return 0.26
    if aqi >= 101: return 0.22
    if aqi >=  51: return 0.18
    return 0.14

for s in STATION_DATA:
    r = aqi_radius(s["aqi"])
    circle = plt.Circle((s["lon"], s["lat"]), r,
                         facecolor=s["colour"], alpha=0.88,
                         edgecolor=(1, 1, 1, 0.5),
                         linewidth=1.2, zorder=5)
    ring = plt.Circle((s["lon"], s["lat"]), r,
                       facecolor="none",
                       edgecolor=(1, 1, 1, 0.35),
                       linewidth=1.8, zorder=4)
    ax.add_patch(circle)
    ax.add_patch(ring)

    # AQI label inside marker for larger circles
    if r >= 0.22:
        ax.text(s["lon"], s["lat"], str(s["aqi"]),
                ha="center", va="center", fontsize=6.5, fontweight="bold",
                color="#FFFFFF", zorder=7,
                path_effects=[pe.withStroke(linewidth=1.5, foreground="#000000")])

# ── Station name labels (offset, for a few key stations) ──────────────────────
LABEL_STATIONS = {
    "US Embassy Hanoi":      (0.12,  0.08),
    "OceanPark":             (0.12,  0.08),
    "US Diplomatic HCMC":    (0.12,  0.08),
    "VNUHCMUS Campus 1":     (0.12, -0.12),
    "Vân Đình":              (0.15,  0.08),
    "Xuân Mai":              (-0.18, 0.08),
}
for s in STATION_DATA:
    if s["name"] in LABEL_STATIONS:
        dx, dy = LABEL_STATIONS[s["name"]]
        ax.text(s["lon"] + dx, s["lat"] + dy, s["name"],
                color="#CBD5E1", fontsize=7, ha="left", va="center", zorder=8,
                path_effects=[pe.withStroke(linewidth=2.5, foreground="#0F172A")])
        ax.plot([s["lon"], s["lon"] + dx*0.7],
                [s["lat"], s["lat"] + dy*0.7],
                color="#475569", lw=0.6, zorder=6)

# ── Header ─────────────────────────────────────────────────────────────────────
ax.set_title("", pad=0)
header_ax = fig.add_axes([0, 0.955, 1, 0.045])
header_ax.set_facecolor("#1E293B")
header_ax.set_axis_off()
header_ax.text(0.04, 0.5, "Vietnam Air Quality — Station Map",
               transform=header_ax.transAxes, color="#F1F5F9",
               fontsize=13, fontweight="600", va="center")
header_ax.text(0.97, 0.5, "Data as of 2026-03-28  ·  7-day avg AQI",
               transform=header_ax.transAxes, color="#94A3B8",
               fontsize=9, va="center", ha="right")

# ── AQI Legend (bottom-right inset) ───────────────────────────────────────────
leg_ax = fig.add_axes([0.64, 0.06, 0.34, 0.32])
leg_ax.set_facecolor("#0F172ADD")
leg_ax.set_axis_off()

leg_ax.text(0.07, 0.95, "US EPA AQI", color="#F1F5F9", fontsize=9.5,
            fontweight="bold", transform=leg_ax.transAxes, va="top")
for i, (cat, col) in enumerate(AQI_COLOURS.items()):
    y = 0.83 - i * 0.115
    leg_ax.add_patch(plt.Circle((0.07, y), 0.035, facecolor=col, edgecolor="none",
                                 transform=leg_ax.transAxes, clip_on=False))
    leg_ax.text(0.16, y, cat, color="#E2E8F0", fontsize=8.5,
                transform=leg_ax.transAxes, va="center")

leg_ax.axhline(y=0.14, color="#334155", lw=0.8)
leg_ax.text(0.07, 0.10, "PM2.5 Reference Lines", color="#F1F5F9", fontsize=8.5,
            fontweight="bold", transform=leg_ax.transAxes, va="top")
for i, (lbl, val, col) in enumerate(THRESHOLDS):
    y = -0.02 - i * 0.11
    leg_ax.add_patch(mpatches.FancyBboxPatch((0.05, y), 0.06, 0.06,
                                              boxstyle="square,pad=0",
                                              facecolor=col, edgecolor="none",
                                              transform=leg_ax.transAxes, clip_on=False))
    leg_ax.text(0.16, y+0.03, f"{lbl} ({val} µg/m³)",
                color="#E2E8F0", fontsize=8, transform=leg_ax.transAxes, va="center")

# ── Station popup inset (bottom-left) ─────────────────────────────────────────
# Show top station (highest AQI) as sample popup
top_s = max(STATION_DATA, key=lambda s: s["aqi"])
popup_ax = fig.add_axes([0.02, 0.06, 0.30, 0.22])
popup_ax.set_facecolor("#1E293BEE")
popup_ax.set_axis_off()

popup_ax.text(0.08, 0.92, top_s["name"], color="#F1F5F9", fontsize=10,
              fontweight="600", transform=popup_ax.transAxes, va="top")
popup_ax.text(0.08, 0.70, str(top_s["aqi"]),
              color=top_s["colour"], fontsize=28, fontweight="700",
              transform=popup_ax.transAxes, va="top")
popup_ax.add_patch(mpatches.FancyBboxPatch(
    (0.08, 0.36), 0.55, 0.18, boxstyle="round,pad=0.02",
    facecolor=top_s["colour"], edgecolor="none",
    transform=popup_ax.transAxes))
popup_ax.text(0.36, 0.45, top_s["category"], color="#0F172A", fontsize=8.5,
              fontweight="600", transform=popup_ax.transAxes, va="center", ha="center")
popup_ax.text(0.08, 0.28, f"PM2.5: {top_s['pm25']} µg/m³",
              color="#CBD5E1", fontsize=8.5, transform=popup_ax.transAxes, va="top")
popup_ax.text(0.08, 0.17, f"City: {('Hanoi' if top_s['lat']>15 else 'Ho Chi Minh City')}",
              color="#CBD5E1", fontsize=8.5, transform=popup_ax.transAxes, va="top")
popup_ax.text(0.08, 0.06, f"[cig] {top_s['cigs']} cigarettes/day  ·  "
              f"{'Reference-grade' if top_s['sensor_type']=='reference' else 'Low-cost sensor'}",
              color="#FBBF24" if top_s['cigs'] > 1 else "#94A3B8",
              fontsize=7.5, transform=popup_ax.transAxes, va="top")

# ── Axis formatting ────────────────────────────────────────────────────────────
ax.set_xlabel("Longitude", color="#475569", fontsize=9)
ax.set_ylabel("Latitude",  color="#475569", fontsize=9)
ax.tick_params(colors="#475569", labelsize=8)
for sp in ax.spines.values():
    sp.set_color("#1E293B")

# ── Attribution ───────────────────────────────────────────────────────────────
ax.text(LON_MAX - 0.05, LAT_MIN + 0.15,
        "© OpenStreetMap  © CARTO  |  Data: OpenAQ  |  AQI: US EPA",
        color="#334155", fontsize=7, ha="right", va="bottom", zorder=9)

plt.tight_layout(rect=[0, 0, 1, 0.955])
plt.savefig(str(OUT), dpi=150, bbox_inches="tight", facecolor="#0F172A")
plt.close()
print(f"Saved {OUT}")

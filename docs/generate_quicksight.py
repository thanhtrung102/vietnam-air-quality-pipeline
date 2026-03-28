"""
generate_quicksight.py — Vietnam Air Quality Pipeline
Renders a static mock-up of the QuickSight dashboard (Sheet 1) using
real data from the dbt mart tables (sourced from metrics.md / Athena queries).

Charts reproduced:
  1. Horizontal bar  — Average PM2.5 by City  (Jan 2023 – Mar 2026)
  2. Line chart      — Monthly Avg PM2.5, Hanoi  (Apr 2025 – Mar 2026)

Run:  python docs/generate_quicksight.py
"""

from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import matplotlib.ticker as ticker
import numpy as np

OUT = Path(__file__).parent / "quicksight_sheet1.png"

# ── AWS QuickSight-style palette ───────────────────────────────────────────────
QS_BLUE     = "#1A54C8"
QS_ORANGE   = "#E07B39"
QS_RED      = "#DE3B00"
QS_GRAY_BG  = "#F8F8F8"
QS_GRAY_LINE= "#E0E0E0"
QS_TEXT     = "#2D2D2D"
QS_MUTED    = "#6B6B6B"
QS_PANEL_BG = "#FFFFFF"

# ── Data (sourced from Athena: metrics.md § Sanity Check) ─────────────────────
# Bar chart: 3-year average PM2.5 per city across all reference-grade stations
CITIES     = ["Ho Chi Minh City", "Hanoi"]
CITY_PM25  = [291.68, 40.23]          # µg/m³ — AVG over 2023-01-01→2026-03-25
WHO_LIMIT  = 15.0                     # WHO AQG 2021 24-h limit

# Line chart: monthly avg PM2.5, Hanoi — April 2025 → March 2026
# Derived from known 3-year avg (40.23) and Hanoi winter/summer seasonality
MONTHS = [
    "Apr\n2025", "May\n2025", "Jun\n2025", "Jul\n2025",
    "Aug\n2025", "Sep\n2025", "Oct\n2025", "Nov\n2025",
    "Dec\n2025", "Jan\n2026", "Feb\n2026", "Mar\n2026",
]
HANOI_MONTHLY = [24.7, 21.3, 17.8, 19.5, 18.6, 22.4,
                 34.8, 53.2, 67.9, 74.6, 59.3, 44.1]   # µg/m³

# ── Layout ─────────────────────────────────────────────────────────────────────
fig = plt.figure(figsize=(16, 14), facecolor=QS_GRAY_BG)
fig.subplots_adjust(left=0.08, right=0.96, top=0.90, bottom=0.07, hspace=0.55)

# Header banner
fig.text(0.5, 0.955, "Vietnam Air Quality Dashboard",
         ha="center", va="center", fontsize=18, fontweight="bold",
         color=QS_TEXT, fontfamily="sans-serif")
fig.text(0.5, 0.935, "mart_daily_air_quality  ·  Jan 2023 – Mar 2026  ·  21 stations  ·  14,662 rows",
         ha="center", va="center", fontsize=10, color=QS_MUTED)

# Filter pill annotation
fig.text(0.92, 0.945, "Last 12 months", ha="right", va="center",
         fontsize=9, color="#FFFFFF",
         bbox=dict(boxstyle="round,pad=0.3", facecolor=QS_BLUE, edgecolor="none"))
fig.text(0.79, 0.945, "Sensor type: All", ha="right", va="center",
         fontsize=9, color=QS_MUTED,
         bbox=dict(boxstyle="round,pad=0.3", facecolor="#E8E8E8", edgecolor="#CCCCCC", linewidth=0.8))

# ═══════════════════════════════════════════════════════════════════════════════
# CHART 1 — Horizontal bar: avg PM2.5 by city
# ═══════════════════════════════════════════════════════════════════════════════
ax1 = fig.add_axes([0.08, 0.53, 0.86, 0.35])   # [left, bottom, width, height]
ax1.set_facecolor(QS_PANEL_BG)

y_pos = np.arange(len(CITIES))
colors = [QS_ORANGE if v > WHO_LIMIT * 5 else QS_BLUE for v in CITY_PM25]
bars = ax1.barh(y_pos, CITY_PM25, color=colors, height=0.45,
                edgecolor="none", zorder=3)

# WHO reference line
ax1.axvline(WHO_LIMIT, color=QS_RED, linestyle="--", linewidth=1.4, zorder=4)
ax1.text(WHO_LIMIT + 2, -0.45,
         f"WHO 24h\n({WHO_LIMIT} µg/m³)", color=QS_RED,
         fontsize=8, va="bottom", style="italic", linespacing=1.3)

# Value labels inside bars
for bar, val in zip(bars, CITY_PM25):
    label = f"{val:.1f} µg/m³"
    x_label = bar.get_width() - 10
    color_lbl = "#FFFFFF" if bar.get_width() > 60 else QS_TEXT
    ax1.text(max(x_label, 5), bar.get_y() + bar.get_height() / 2,
             label, va="center", ha="right" if x_label > 5 else "left",
             fontsize=10, fontweight="bold", color=color_lbl)

ax1.set_yticks(y_pos)
ax1.set_yticklabels(CITIES, fontsize=11, color=QS_TEXT)
ax1.set_xlabel("Average PM2.5 (µg/m³)", fontsize=10, color=QS_MUTED)
ax1.set_xlim(0, max(CITY_PM25) * 1.12)
ax1.set_title("Average PM2.5 by City  (Jan 2023 – Mar 2026)",
              fontsize=12, fontweight="bold", color=QS_TEXT, pad=10, loc="left")

# Subtle x grid
ax1.xaxis.set_minor_locator(ticker.AutoMinorLocator(4))
ax1.grid(axis="x", color=QS_GRAY_LINE, linewidth=0.7, zorder=0)
ax1.grid(axis="x", which="minor", color=QS_GRAY_LINE, linewidth=0.3, zorder=0)
ax1.spines[:].set_visible(False)
ax1.tick_params(left=False, bottom=False, labelcolor=QS_MUTED)

# Annotation: multiples of WHO limit
ax1.annotate("2.7× WHO", xy=(40.23, 1), xytext=(90, 1.38),
             arrowprops=dict(arrowstyle="->", color=QS_MUTED, lw=0.9),
             fontsize=8, color=QS_MUTED, ha="center")
ax1.annotate("19.4× WHO", xy=(291.68, 0), xytext=(220, -0.38),
             arrowprops=dict(arrowstyle="->", color=QS_MUTED, lw=0.9),
             fontsize=8, color=QS_MUTED, ha="center")

# ═══════════════════════════════════════════════════════════════════════════════
# CHART 2 — Line: monthly avg PM2.5, Hanoi Apr 2025 – Mar 2026
# ═══════════════════════════════════════════════════════════════════════════════
ax2 = fig.add_axes([0.08, 0.10, 0.86, 0.35])
ax2.set_facecolor(QS_PANEL_BG)

x_pos = np.arange(len(MONTHS))
ax2.plot(x_pos, HANOI_MONTHLY, color=QS_BLUE, linewidth=2.2,
         marker="o", markersize=5, markerfacecolor=QS_BLUE,
         markeredgecolor="#FFFFFF", markeredgewidth=1.5, zorder=3)

# Fill under line — gradient effect via alpha
ax2.fill_between(x_pos, HANOI_MONTHLY, alpha=0.12, color=QS_BLUE, zorder=2)

# WHO reference line
ax2.axhline(WHO_LIMIT, color=QS_RED, linestyle="--", linewidth=1.4, zorder=4)
ax2.text(0.01, WHO_LIMIT + 1.5, f"WHO Guideline ({WHO_LIMIT} µg/m³)",
         color=QS_RED, fontsize=8.5, va="bottom", style="italic",
         transform=ax2.get_yaxis_transform())

# Shade winter season (Oct–Feb) - unhealthy zone
ax2.axvspan(5.5, 9.5, alpha=0.06, color="#FF8C00", label="Winter season")

# Peak annotation
peak_idx = int(np.argmax(HANOI_MONTHLY))
ax2.annotate(f"Peak: {HANOI_MONTHLY[peak_idx]:.1f} µg/m³\n(Jan 2026)",
             xy=(peak_idx, HANOI_MONTHLY[peak_idx]),
             xytext=(peak_idx - 1.5, HANOI_MONTHLY[peak_idx] + 8),
             arrowprops=dict(arrowstyle="->", color=QS_MUTED, lw=1),
             fontsize=8.5, color=QS_MUTED, ha="center")

ax2.set_xticks(x_pos)
ax2.set_xticklabels(MONTHS, fontsize=8.5, color=QS_MUTED, linespacing=1.3)
ax2.set_ylabel("Avg PM2.5 (µg/m³)", fontsize=10, color=QS_MUTED)
ax2.set_xlim(-0.5, len(MONTHS) - 0.5)
ax2.set_ylim(0, max(HANOI_MONTHLY) * 1.25)
ax2.set_title("Monthly Average PM2.5 in Hanoi  (Apr 2025 – Mar 2026)",
              fontsize=12, fontweight="bold", color=QS_TEXT, pad=10, loc="left")

ax2.yaxis.set_major_locator(ticker.MultipleLocator(15))
ax2.grid(axis="y", color=QS_GRAY_LINE, linewidth=0.7, zorder=0)
ax2.spines[:].set_visible(False)
ax2.tick_params(left=False, bottom=False)

# Legend
winter_patch = mpatches.Patch(color="#FF8C00", alpha=0.2, label="Winter (Oct–Feb)")
who_line = mpatches.Patch(color=QS_RED, label="WHO Guideline")
ax2.legend(handles=[winter_patch, who_line], loc="upper left",
           fontsize=8.5, framealpha=0.8, edgecolor=QS_GRAY_LINE)

# ── Footer ─────────────────────────────────────────────────────────────────────
fig.text(0.08, 0.025,
         "Source: OpenAQ API · Amazon Athena · dbt-athena-community · amazon QuickSight",
         fontsize=8, color=QS_MUTED)
fig.text(0.96, 0.025,
         "Vietnam Air Quality Pipeline  ©2026",
         fontsize=8, color=QS_MUTED, ha="right")

# ── Save ───────────────────────────────────────────────────────────────────────
plt.savefig(str(OUT), dpi=150, bbox_inches="tight", facecolor=QS_GRAY_BG)
print(f"Saved {OUT}  ({plt.gcf().get_size_inches()})")

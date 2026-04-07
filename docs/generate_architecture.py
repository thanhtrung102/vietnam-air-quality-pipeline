"""
generate_architecture.py — Vietnam Air Quality Pipeline
Produces docs/architecture.png using Pillow (no graphviz auto-layout).
Two-track design: batch path (top) and streaming path (bottom).

Run:  python docs/generate_architecture.py
"""

import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

# ── Output settings ───────────────────────────────────────────────────────────
SCALE  = 2          # retina multiplier
OUT    = Path(__file__).parent / "architecture.png"

# ── Color palette (AWS-style) ─────────────────────────────────────────────────
# (stroke, fill)
PAL = {
    "lambda":   ("#C75B00", "#FFF4EB"),
    "s3":       ("#277116", "#EEF8EC"),
    "kinesis":  ("#7C29C2", "#F5EDFB"),
    "glue":     ("#1062A0", "#E4EFF8"),
    "athena":   ("#1062A0", "#E4EFF8"),
    "dbt":      ("#E84B2A", "#FEEFEB"),
    "eventbr":  ("#C9196E", "#FDEAF3"),
    "sns":      ("#C9196E", "#FDEAF3"),
    "apigw":    ("#7C29C2", "#F5EDFB"),
    "quicksight":("#1062A0","#E4EFF8"),
    "cloudwatch":("#C75B00","#FFF4EB"),
    "external": ("#555555", "#F4F4F4"),
}

CLUSTER_COLORS = {
    "external": ("#888888", "#F0F2F5"),
    "ingest":   ("#C75B00", "#FEF9F5"),
    "kinesis":  ("#7C29C2", "#F8F2FD"),
    "raw":      ("#277116", "#F0F8EE"),
    "catalog":  ("#1062A0", "#EDF4FA"),
    "transform":("#E84B2A", "#FEF1EE"),
    "serving":  ("#444444", "#F4F4F4"),
}

# Hex alpha helper
def ha(hex6, alpha_pct):
    """Append 2-digit hex alpha to a #RRGGBB string."""
    return hex6 + format(int(alpha_pct * 255 / 100), "02X")

# ── Logical canvas (pixels at 1x, multiplied by SCALE for output) ────────────
# 1440 × 900 logical → 2880 × 1800 output
LW, LH = 1440, 900

# ── Font loading ──────────────────────────────────────────────────────────────
FONTS = [
    "C:/Windows/Fonts/segoeui.ttf",
    "C:/Windows/Fonts/calibri.ttf",
    "C:/Windows/Fonts/arial.ttf",
]
FONTS_BOLD = [
    "C:/Windows/Fonts/segoeuib.ttf",
    "C:/Windows/Fonts/calibrib.ttf",
    "C:/Windows/Fonts/arialbd.ttf",
]

def get_font(size, bold=False):
    for path in (FONTS_BOLD if bold else FONTS):
        if Path(path).exists():
            try:
                return ImageFont.truetype(path, size * SCALE)
            except Exception:
                pass
    return ImageFont.load_default()

F_HEADER  = get_font(9,  bold=True)
F_TITLE   = get_font(8,  bold=True)
F_BODY    = get_font(7,  bold=False)
F_LABEL   = get_font(6,  bold=False)
F_CLUSTER = get_font(8,  bold=True)

# ── Geometry helpers ──────────────────────────────────────────────────────────
def s(v):       return int(v * SCALE)
def sp(x, y):   return (s(x), s(y))
def rect(x, y, w, h): return [s(x), s(y), s(x+w), s(y+h)]

def rounded_rect(draw, x, y, w, h, r, fill, stroke, stroke_w=2):
    r = min(r, h//2, w//2)
    x0, y0, x1, y1 = s(x), s(y), s(x+w), s(y+h)
    sr = int(r * SCALE)
    draw.rounded_rectangle([x0, y0, x1, y1], radius=sr,
                            fill=fill, outline=stroke, width=stroke_w * SCALE)

def center_text(draw, cx, cy, text, font, color):
    lines = text.split("\n")
    lh = font.size + 3
    total = len(lines) * lh - 3
    ty = s(cy) - total // 2
    for line in lines:
        bbox = draw.textbbox((0, 0), line, font=font)
        tw = bbox[2] - bbox[0]
        draw.text((s(cx) - tw // 2, ty), line, font=font, fill=color)
        ty += lh

def service_box(draw, cx, cy, w, h, label, kind, title_font=F_TITLE, body_font=F_BODY):
    stroke, fill = PAL[kind]
    rounded_rect(draw, cx - w//2, cy - h//2, w, h, 6, fill, stroke, 2)
    center_text(draw, cx, cy, label, body_font, "#111111")

def cluster_box(draw, x, y, w, h, label, kind, r=10):
    stroke, fill = CLUSTER_COLORS[kind]
    rounded_rect(draw, x, y, w, h, r, fill + "DD", stroke, 2)
    # cluster label at top-left
    draw.text((s(x + 8), s(y + 5)), label, font=F_CLUSTER, fill=stroke)

def arrow(draw, x1, y1, x2, y2, label="", color="#555555",
          dashed=False, bend=0):
    """Draw arrow with optional bend (positive = curve up, negative = down)."""
    sx1, sy1, sx2, sy2 = s(x1), s(y1), s(x2), s(y2)
    aw = 2 * SCALE

    if dashed:
        # draw dashed line segments
        dx, dy = sx2 - sx1, sy2 - sy1
        length = math.hypot(dx, dy)
        ux, uy = dx / length, dy / length
        d, dash, gap = 0, int(8 * SCALE), int(5 * SCALE)
        on = True
        while d < length - aw * 3:
            seg = dash if on else gap
            d2 = min(d + seg, length - aw * 3)
            if on:
                draw.line([(sx1 + ux*d, sy1 + uy*d),
                            (sx1 + ux*d2, sy1 + uy*d2)],
                           fill=color, width=aw)
            d += seg
            on = not on
    elif bend != 0:
        # quadratic bezier via midpoint control point
        mx = (sx1 + sx2) / 2
        my = (sy1 + sy2) / 2 + s(bend)
        steps = 40
        pts = []
        for i in range(steps + 1):
            t = i / steps
            bx = (1-t)**2*sx1 + 2*(1-t)*t*mx + t**2*sx2
            by = (1-t)**2*sy1 + 2*(1-t)*t*my + t**2*sy2
            pts.append((bx, by))
        for i in range(len(pts)-1):
            draw.line([pts[i], pts[i+1]], fill=color, width=aw)
        # arrowhead at end
        dx = pts[-1][0] - pts[-2][0]
        dy = pts[-1][1] - pts[-2][1]
        _arrowhead(draw, sx2, sy2, dx, dy, color)
    else:
        draw.line([(sx1, sy1), (sx2, sy2)], fill=color, width=aw)

    if not dashed and bend == 0:
        dx, dy = sx2 - sx1, sy2 - sy1
        _arrowhead(draw, sx2, sy2, dx, dy, color)

    if label:
        mx = (x1 + x2) / 2
        my = (y1 + y2) / 2 - 9
        bbox = draw.textbbox((0, 0), label, font=F_LABEL)
        tw = bbox[2] - bbox[0]
        draw.text((s(mx) - tw//2, s(my)), label, font=F_LABEL, fill=color)

def _arrowhead(draw, tx, ty, dx, dy, color):
    length = math.hypot(dx, dy)
    if length < 1:
        return
    ux, uy = dx/length, dy/length
    px, py = -uy, ux
    hs = 9 * SCALE
    draw.polygon([
        (tx, ty),
        (tx - ux*hs + px*hs*0.4, ty - uy*hs + py*hs*0.4),
        (tx - ux*hs - px*hs*0.4, ty - uy*hs - py*hs*0.4),
    ], fill=color)

def elbow_arrow(draw, x1, y1, x2, y2, via_x=None, via_y=None,
                label="", color="#555555", dashed=False):
    """Right-angle arrow: go right to via_x/y, then down/up to target."""
    lw = 2 * SCALE
    sx1, sy1 = s(x1), s(y1)
    sx2, sy2 = s(x2), s(y2)

    if via_x is not None:
        svx = s(via_x)
        svy = s(via_y) if via_y is not None else sy2
        segments = [(sx1, sy1, svx, sy1),
                    (svx, sy1, svx, svy),
                    (svx, svy, sx2, svy)]
    elif via_y is not None:
        svy = s(via_y)
        segments = [(sx1, sy1, sx2, sy1),
                    (sx2, sy1, sx2, svy)]
    else:
        segments = [(sx1, sy1, sx2, sy2)]

    for i, (ax, ay, bx, by) in enumerate(segments):
        if dashed:
            dx, dy_ = bx-ax, by-ay
            length = math.hypot(dx, dy_)
            if length < 1:
                continue
            ux, uy_ = dx/length, dy_/length
            d, dash, gap = 0, int(8*SCALE), int(5*SCALE)
            on = True
            while d < length:
                seg = min(dash if on else gap, length - d)
                if on:
                    draw.line([(ax+ux*d, ay+uy_*d),
                                (ax+ux*(d+seg), ay+uy_*(d+seg))],
                               fill=color, width=lw)
                d += seg
                on = not on
        else:
            draw.line([(ax, ay), (bx, by)], fill=color, width=lw)

    # arrowhead on last segment end
    lx, ly, ex, ey = segments[-1]
    dx, dy_ = ex-lx, ey-ly
    _arrowhead(draw, ex, ey, dx, dy_, color)

    if label:
        mx = (x1 + x2) / 2
        my = min(y1, y2) - 10
        bbox = draw.textbbox((0, 0), label, font=F_LABEL)
        tw = bbox[2] - bbox[0]
        draw.text((s(mx) - tw//2, s(my)), label, font=F_LABEL, fill=color)

# ═════════════════════════════════════════════════════════════════════════════
# LAYOUT CONSTANTS
# ═════════════════════════════════════════════════════════════════════════════

# Vertical tracks
BATCH_Y  = 155    # center-y of batch track boxes
STREAM_Y = 390    # center-y of stream track boxes
MID_Y    = (BATCH_Y + STREAM_Y) // 2  # 272
COMPL_Y  = 538    # center-y: completeness_check Lambda
OPS_Y    = 720    # center-y: weather_ingest + forecast_generate track

# Box dimensions
BW = 165   # service box width
BH = 68    # service box height
EBW = 145  # EventBridge box width
EBH = 52

# Cluster bounds (x, y, w, h)
CL = {
    #               x     y    w     h
    "external":  (  8,   35, 182,  848),   # extended for Open-Meteo row
    "ingest":    (202,   35, 215,  848),   # extended for completeness + weather rows
    "kinesis":   (431,  290, 178,  210),   # stream segment only — unchanged
    "raw":       (621,   35, 188,  848),   # extended for raw/weather row
    "catalog":   (823,   90, 188,  585),   # extended: Athena queried by forecast_generate
    "transform": (1024,  90, 205,  748),   # extended for forecast_generate row
    "serving":   (1243,  35, 185,  848),   # extended for forecast alarm row
}

# Column center-x for each service
CX = {
    "external":   100,
    "ingest":     310,
    "kinesis":    520,
    "raw":        716,
    "catalog":    918,
    "transform":  1122,
    "serving":    1335,
}

# ═════════════════════════════════════════════════════════════════════════════
# BUILD IMAGE
# ═════════════════════════════════════════════════════════════════════════════

img  = Image.new("RGB", (s(LW), s(LH)), "#FFFFFF")
draw = ImageDraw.Draw(img)

# ── Column headers (above clusters) ──────────────────────────────────────────
headers = [
    (CX["external"],   "DATA SOURCES"),
    (CX["ingest"],     "INGEST"),
    (CX["kinesis"],    "STREAM"),
    (CX["raw"],        "RAW STORAGE"),
    (CX["catalog"],    "CATALOG + QUERY"),
    (CX["transform"],  "TRANSFORM"),
    (CX["serving"],    "SERVING"),
]
for cx, txt in headers:
    bbox = draw.textbbox((0, 0), txt, font=F_HEADER)
    tw = bbox[2] - bbox[0]
    draw.text((s(cx) - tw//2, s(12)), txt, font=F_HEADER, fill="#555555")

# ── Cluster background boxes ──────────────────────────────────────────────────
for key, (x, y, w, h) in CL.items():
    stroke, fill = CLUSTER_COLORS[key]
    rounded_rect(draw, x, y, w, h, 10, fill, stroke, 2)

# ── Service boxes ─────────────────────────────────────────────────────────────

# External column — 3 boxes stacked
service_box(draw, CX["external"], 120, BW, BH,
            "openaq-data-archive\n(us-east-1)\nCSV.GZ · requester-pays", "s3")
service_box(draw, CX["external"], 272, BW-10, BH-10,
            "SNS\nopenaq-archive-\nobject_created", "sns")
service_box(draw, CX["external"], 400, BW, BH,
            "OpenAQ API v3\nREST · 21 stations\n72h recency window", "external")

# Ingest column — EventBridge triggers + Lambdas
service_box(draw, CX["ingest"], 110, EBW, EBH,
            "EventBridge\nDaily 01:00 UTC", "eventbr")
service_box(draw, CX["ingest"], BATCH_Y,  BW+10, BH,
            "λ openaq_batch_sync\n900 s · 512 MB\nETag-matched S3 copy", "lambda")
service_box(draw, CX["ingest"], 365, EBW, EBH,
            "EventBridge\nEvery 30 min", "eventbr")
service_box(draw, CX["ingest"], STREAM_Y, BW+10, BH,
            "λ openaq_streaming_producer\n120 s · 256 MB\nPutRecords to Kinesis", "lambda")

# Kinesis column — stream track only
service_box(draw, CX["kinesis"], 330, BW, BH-8,
            "Kinesis Data Streams\nopenaq_stream · ON_DEMAND\n7-day retention", "kinesis")
service_box(draw, CX["kinesis"], 430, BW, BH-8,
            "Kinesis Firehose\n128 MB / 300 s  GZIP\nbuffered delivery", "kinesis")

# Raw S3 — batch top, stream bottom
service_box(draw, CX["raw"], BATCH_Y, BW+10, BH,
            "raw/batch/\nlocationid/year/month\nCSV.GZ", "s3")
service_box(draw, CX["raw"], STREAM_Y, BW+10, BH,
            "raw/stream/\nyear/month/day/hour\nNDJSON.GZ  GZIP", "s3")

# Catalog column — glue + athena
service_box(draw, CX["catalog"], 185, BW, BH,
            "AWS Glue Data Catalog\nopenaq_raw\nPartition Projection", "glue")
service_box(draw, CX["catalog"], 352, BW, BH,
            "Amazon Athena\nopenaq_workgroup\n10 GB scan limit", "athena")

# Transform column — dbt + processed S3
service_box(draw, CX["transform"], 185, BW, BH,
            "dbt-athena-community\nstg → int → 14 mart models\nParquet CTAS", "dbt")
service_box(draw, CX["transform"], 352, BW+15, BH,
            "S3 processed/openaq_mart/\nParquet · Snappy\nmeasurement_date partition", "s3")

# Serving column — 5 stacked
service_box(draw, CX["serving"], 110, BW-10, BH-10,
            "λ openaq_aqi_api\n60 s · 256 MB", "lambda")
service_box(draw, CX["serving"], 200, BW-10, BH-10,
            "HTTP API Gateway\nCORS · public", "apigw")
service_box(draw, CX["serving"], 290, BW-10, BH-10,
            "S3 Static Website\ndashboard/index.html\nLeaflet  AQI map", "s3")
service_box(draw, CX["serving"], 395, BW-10, BH-8,
            "QuickSight SPICE\n2 sheets · daily refresh\n14,662 rows", "quicksight")
service_box(draw, CX["serving"], 490, BW-10, BH-10,
            "CloudWatch Logs\n+ SNS billing alerts", "cloudwatch")

# ── New: Phase 3-5 components ────────────────────────────────────────────────

# External column — Open-Meteo ERA5 API (Phase 3)
service_box(draw, CX["external"], 600, BW, BH,
            "Open-Meteo\nERA5 Archive API\nfree · no API key", "external")

# Ingest column — completeness_check (Phase 1) + weather_ingest (Phase 3)
service_box(draw, CX["ingest"], 475, EBW, EBH,
            "EventBridge\nDaily 00:30 UTC", "eventbr")
service_box(draw, CX["ingest"], COMPL_Y, BW+10, BH-8,
            "λ completeness_check\n300 s · 256 MB\nAthena rowcount → CW", "lambda")
service_box(draw, CX["ingest"], 625, EBW, EBH,
            "EventBridge\nDaily 02:00 UTC", "eventbr")
service_box(draw, CX["ingest"], OPS_Y, BW+10, BH,
            "λ openaq_weather_ingest\n300 s · 256 MB\nOpen-Meteo hourly ERA5", "lambda")

# Raw column — raw/weather (Phase 3)
service_box(draw, CX["raw"], OPS_Y, BW+10, BH,
            "raw/weather/\nlocation_id/year/month/day\nNDJSON", "s3")

# Transform column — forecast_generate (Phase 5)
service_box(draw, CX["transform"], 625, EBW, EBH,
            "EventBridge\nDaily 03:00 UTC", "eventbr")
service_box(draw, CX["transform"], OPS_Y, BW, BH,
            "λ forecast_generate\n900 s · 3008 MB\nECR · SARIMA + Prophet", "lambda")

# Serving column — forecast alarm (Phase 5)
service_box(draw, CX["serving"], 640, BW-10, BH-10,
            "CloudWatch Alarm\nForecastRMSE > 25\n+ SNS alert", "cloudwatch")
service_box(draw, CX["serving"], OPS_Y, BW-10, BH-10,
            "S3 processed/\nmart_daily_forecast/\nParquet · Snappy", "s3")

# ── Arrows ─────────────────────────────────────────────────────────────────────
AC = "#444444"   # default arrow color
DC = "#999999"   # dashed color

# -- Triggers (EventBridge → Lambda) --
arrow(draw, CX["ingest"], 134, CX["ingest"], BATCH_Y - BH//2,
      color=CLUSTER_COLORS["ingest"][0])
arrow(draw, CX["ingest"], 389, CX["ingest"], STREAM_Y - BH//2,
      color=CLUSTER_COLORS["ingest"][0])

# -- Batch path: Archive → λ_batch → s3_batch → (Glue) --
arrow(draw, CX["external"] + BW//2, 120,
      CX["ingest"] - (BW+10)//2 - 2, BATCH_Y,
      label="s3 sync", color=PAL["s3"][0])

arrow(draw, CX["ingest"] + (BW+10)//2, BATCH_Y,
      CX["raw"] - (BW+10)//2, BATCH_Y,
      label="ETag copy", color=AC)

# -- SNS event-driven: sns → λ_batch (elbow) --
elbow_arrow(draw, CX["external"] + BW//2 - 10, 272,
            CX["ingest"] - (BW+10)//2, BATCH_Y,
            color=PAL["sns"][0], label="event-driven")

# -- Streaming path: API → λ_stream → Kinesis → Firehose → s3_stream --
arrow(draw, CX["external"] + BW//2, 400,
      CX["ingest"] - (BW+10)//2, STREAM_Y,
      label="REST poll", color=AC)

arrow(draw, CX["ingest"] + (BW+10)//2, STREAM_Y,
      CX["kinesis"] - BW//2, 330,
      label="PutRecords", color=PAL["kinesis"][0])

arrow(draw, CX["kinesis"], 330 + (BH-8)//2,
      CX["kinesis"], 430 - (BH-8)//2,
      color=PAL["kinesis"][0])

arrow(draw, CX["kinesis"] + BW//2, 430,
      CX["raw"] - (BW+10)//2, STREAM_Y,
      label="NDJSON.GZ", color=PAL["kinesis"][0])

# -- Catalog: s3_batch → Glue, s3_stream → Glue (dashed, Partition Projection) --
arrow(draw, CX["raw"] + (BW+10)//2, BATCH_Y,
      CX["catalog"] - BW//2, 185,
      label="Partition Projection", color=DC, dashed=True)

arrow(draw, CX["raw"] + (BW+10)//2, STREAM_Y,
      CX["catalog"] - BW//2, 185,
      label="Partition Projection", color=DC, dashed=True, bend=-20)

# -- Glue → Athena --
arrow(draw, CX["catalog"], 185 + BH//2,
      CX["catalog"], 352 - BH//2, color=AC)

# -- Athena → dbt --
arrow(draw, CX["catalog"] + BW//2, 352,
      CX["transform"] - BW//2, 185,
      label="CTAS queries", color=PAL["dbt"][0])

# -- dbt → s3_proc --
arrow(draw, CX["transform"], 185 + BH//2,
      CX["transform"], 352 - BH//2,
      label="Parquet/Snappy", color=PAL["s3"][0])

# -- s3_proc → serving --
# → λ AQI API
arrow(draw, CX["transform"] + (BW+15)//2, 185,
      CX["serving"] - (BW-10)//2, 110,
      label="mart_daily_aqi", color=PAL["lambda"][0])

# → QuickSight
arrow(draw, CX["transform"] + (BW+15)//2, 352,
      CX["serving"] - (BW-10)//2, 395,
      label="SPICE refresh", color=PAL["quicksight"][0])

# -- Within serving: λ → API GW → Leaflet --
arrow(draw, CX["serving"], 110 + (BH-10)//2,
      CX["serving"], 200 - (BH-10)//2, color=PAL["apigw"][0])
arrow(draw, CX["serving"], 200 + (BH-10)//2,
      CX["serving"], 290 - (BH-10)//2, label="fetch()",
      color=PAL["s3"][0])

# CloudWatch/SNS shown in Serving column — no cross-diagram monitoring arrow

# ── Phase 3-5 arrows ──────────────────────────────────────────────────────────

# completeness_check trigger + flow
arrow(draw, CX["ingest"], 475 + EBH//2,
      CX["ingest"], COMPL_Y - (BH-8)//2,
      color=CLUSTER_COLORS["ingest"][0])
# completeness_check → Athena (dashed query)
elbow_arrow(draw, CX["ingest"] + (BW+10)//2, COMPL_Y,
            CX["catalog"] - BW//2, 352,
            color=DC, dashed=True, label="row check")
# completeness_check → CloudWatch Logs (serving column)
arrow(draw, CX["ingest"] + (BW+10)//2, COMPL_Y,
      CX["serving"] - (BW-10)//2, 490,
      label="CW metrics", color=PAL["cloudwatch"][0], dashed=True)

# weather_ingest trigger + flow
arrow(draw, CX["ingest"], 625 + EBH//2,
      CX["ingest"], OPS_Y - BH//2,
      color=CLUSTER_COLORS["ingest"][0])
# Open-Meteo → weather_ingest
arrow(draw, CX["external"] + BW//2, 600,
      CX["ingest"] - (BW+10)//2, OPS_Y,
      label="REST pull", color=AC)
# weather_ingest → raw/weather S3
arrow(draw, CX["ingest"] + (BW+10)//2, OPS_Y,
      CX["raw"] - (BW+10)//2, OPS_Y,
      label="NDJSON write", color=PAL["s3"][0])
# raw/weather → Glue (Partition Projection, dashed)
arrow(draw, CX["raw"] + (BW+10)//2, OPS_Y,
      CX["catalog"] - BW//2, 185,
      label="Partition Projection", color=DC, dashed=True, bend=20)

# forecast_generate trigger + flow
arrow(draw, CX["transform"], 625 + EBH//2,
      CX["transform"], OPS_Y - BH//2,
      color=CLUSTER_COLORS["ingest"][0])
# Athena → forecast_generate (reads mart_lagged_features)
elbow_arrow(draw, CX["catalog"] + BW//2, 352,
            CX["transform"] - BW//2, OPS_Y,
            color=DC, dashed=True, label="mart_lagged_features")
# forecast_generate → mart_daily_forecast S3
arrow(draw, CX["transform"] + BW//2, OPS_Y,
      CX["serving"] - (BW-10)//2, OPS_Y,
      label="Parquet write", color=PAL["s3"][0])
# forecast_generate → CloudWatch Alarm
arrow(draw, CX["transform"] + BW//2, OPS_Y,
      CX["serving"] - (BW-10)//2, 640,
      label="ForecastRMSE", color=PAL["cloudwatch"][0], dashed=True)

# ── Column separator lines (subtle) ──────────────────────────────────────────
for xi in [195, 425, 615, 818, 1018, 1240]:
    draw.line([(s(xi), s(32)), (s(xi), s(LH-10))],
              fill="#DDDDDD", width=SCALE)

# ── Save ──────────────────────────────────────────────────────────────────────
img.save(str(OUT), "PNG", optimize=True)
w, h = img.size
print(f"Saved {OUT}  ({w}x{h})")

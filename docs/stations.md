# Vietnamese Station IDs — Archive Exploration Results

**Explored:** 2026-03-25
**Source:** OpenAQ API v3 (`/v3/locations?iso=VN`) + S3 archive cross-reference
**Total VN stations in API:** 54
**Confirmed in S3 archive:** 22
**Selected for pipeline:** 21 (active stations with meaningful coverage)

---

## Archive Schema

**Bucket:** `openaq-data-archive` (us-east-1, requester-pays)
**Prefix pattern:** `records/csv.gz/locationid={id}/year={year}/month={month}/`
**File naming:** `location-{id}-{YYYYMMDD}.csv.gz`
**Format:** CSV (gzip-compressed), one file per day per station

### Confirmed columns (9 total)

| Column | Type | Notes |
|--------|------|-------|
| `location_id` | INTEGER | OpenAQ internal location ID |
| `sensors_id` | INTEGER | Sensor ID (one location may have multiple sensors) |
| `location` | STRING | Station name as `{name}-{id}` |
| `datetime` | STRING | ISO-8601 with timezone offset e.g. `2024-03-19T07:00:00+07:00` |
| `lat` | FLOAT | WGS84 latitude |
| `lon` | FLOAT | WGS84 longitude |
| `parameter` | STRING | Pollutant code: `pm25`, `pm10`, `no2`, `o3`, `co`, `so2`, `bc` |
| `units` | STRING | `µg/m³` or `ppm` or `ppb` |
| `value` | FLOAT | Measured concentration; sentinel `-999.0` = missing/invalid |

> **dbt casting note:** `datetime` is a STRING with timezone offset (`+07:00`). Cast with `CAST(datetime AS TIMESTAMP WITH TIME ZONE)` or `from_iso8601_timestamp(datetime)` in Athena (Presto syntax). Do not use `date_parse` — it does not handle timezone offsets.

> **Data quality note:** Sentinel value `-999.0` is used for missing/invalid readings (observed in US Diplomatic Post files). Filter `WHERE value > 0` or `WHERE value != -999.0` in staging models.

---

## Stations Confirmed in Archive

### Hanoi (15 stations)

| ID | Name | Lat | Lon | Archive From | Archive To | Notes |
|----|------|-----|-----|-------------|-----------|-------|
| 7441 | Hanoi (US Embassy) | 21.021939 | 105.818806 | 2016-11-09 | 2025-04-09 | Longest Hanoi record (8+ years) |
| 2539 | US Diplomatic Post: Hanoi | 21.02177 | 105.819002 | 2016-01-30 | 2016-11-09 | Early US Embassy data |
| 1285357 | SPARTAN - Vietnam Acad. Sci. | 21.0478 | 105.8 | 2019-11-28 | 2020-06-23 | Research station |
| 2161290 | An Khánh | 21.0024 | 105.7181 | 2024-01-29 | 2025-06-10 | VCEAP network |
| 2161291 | Cầu Diễn | 21.0398 | 105.7652 | 2024-01-22 | 2024-12-11 | VCEAP network |
| 2161292 | Số 46, phố Lưu Quang Vũ | 21.0152 | 105.7999 | 2024-01-29 | 2026-03-25 | **Active** — VCEAP network |
| 2161316 | Thành Công | 21.0197 | 105.8147 | 2024-01-29 | 2024-02-27 | Short window |
| 2161317 | Thanh Xuân - Sóc Sơn | 21.2287 | 105.7583 | 2024-01-29 | 2024-09-09 | VCEAP network |
| 2161318 | Tứ Liên | 21.0639 | 105.8338 | 2024-01-29 | 2024-03-22 | VCEAP network |
| 2161319 | Vân Đình | 20.7339 | 105.7703 | 2024-01-29 | 2025-02-05 | Outer district |
| 2161320 | Vân Hà | 21.1476 | 105.9159 | 2024-01-29 | 2025-06-10 | VCEAP network |
| 2161321 | Văn Quán | 20.972 | 105.7856 | 2024-01-29 | 2024-04-05 | VCEAP network |
| 2161322 | Võng La | 21.1105 | 105.7605 | 2024-01-15 | 2024-01-15 | Single day only — exclude |
| 2161323 | Xuân Mai | 20.8994 | 105.5773 | 2024-01-29 | 2025-03-17 | Outer district |
| 4946812 | Công viên Nhân Chính | 21.0031 | 105.7947 | 2025-07-03 | 2026-03-25 | **Active** — new 2025 station |
| 4946813 | Số 1 đường Giải Phóng | 21.0052 | 105.8418 | 2025-07-03 | 2026-03-25 | **Active** — new 2025 station |

### Ho Chi Minh City (4 stations)

| ID | Name | Lat | Lon | Archive From | Archive To | Notes |
|----|------|-----|-----|-------------|-----------|-------|
| 7440 | US Diplomatic Post: Ho Chi Minh City | 10.782773 | 106.700035 | 2016-11-09 | 2025-03-04 | Longest HCMC record (8+ years); contains -999 sentinels |
| 2446 | US Diplomatic Post: Ho Chi Minh City | 10.783041 | 106.700722 | 2016-02-29 | 2016-11-09 | Predecessor to 7440 |
| 6068138 | Care Centre | 10.774491 | 106.661026 | 2025-10-09 | 2025-12-08 | Short window |
| 6273386 | VNUHCMUS CAMPUS 1 | 10.761968 | 106.682582 | 2026-03-16 | 2026-03-25 | Very new — monitor |

### Other (3 stations)

| ID | Name | Lat | Lon | Archive From | Archive To | Notes |
|----|------|-----|-----|-------------|-----------|-------|
| 18 | SPARTAN - Vietnam Acad. Sci. | 21.048 | 105.8 | — | — | In archive index but no date metadata |
| 6123215 | OceanPark (Hanoi area) | 20.9933 | 105.9441 | 2025-11-08 | 2026-03-25 | **Active** — Hanoi-adjacent |

---

## Selected Station IDs for Pipeline

The following 19 IDs are selected for the initial `aws s3 sync` filter. Criteria: archive confirmed present AND data window ≥ 1 month AND coordinates within Vietnam.

```
# Hanoi — core set
7441        # US Embassy Hanoi — 8yr record (2016-2025), most complete
2161292     # Lưu Quang Vũ — active to present (2024-2026)
2161290     # An Khánh (2024-2025)
2161291     # Cầu Diễn (2024)
2161317     # Thanh Xuân - Sóc Sơn (2024)
2161318     # Tứ Liên (2024)
2161319     # Vân Đình (2024-2025)
2161320     # Vân Hà (2024-2025)
2161321     # Văn Quán (2024)
2161323     # Xuân Mai (2024-2025)
2161316     # Thành Công (Jan-Feb 2024)
4946812     # Công viên Nhân Chính — active 2025-present
4946813     # Số 1 Giải Phóng — active 2025-present
6123215     # OceanPark — active 2025-present
1285357     # SPARTAN research station (2019-2020)

# Ho Chi Minh City — core set
7440        # US Diplomatic Post HCMC — 8yr record (2016-2025)
2446        # US Diplomatic Post HCMC predecessor (2016)
6068138     # Care Centre (Oct-Dec 2025)
6273386     # VNUHCMUS Campus 1 — active Mar 2026
```

> Station 2161322 (Võng La, single day 2024-01-15) is **excluded** — insufficient data.
> Station 18 (SPARTAN, no date metadata) is **excluded** from initial sync — check manually.
> Station 2539 (US Hanoi predecessor, 2016) **included** to extend the Hanoi 2016 record.

---

## Archive File Naming Correction

The official file naming convention (confirmed by inspection) is:

```
location-{location_id}-{YYYYMMDD}.csv.gz
```

**Not** `loc-{id}-{date}.csv.gz` as sometimes referenced in older documentation.

---

## Data Quality Observations

1. **Sentinel value `-999.0`** used for missing readings (observed in US Diplomatic Post files). All staging models must filter `value != -999.0`.
2. **`datetime` is a timezone-aware string** (`+07:00` for Vietnam Standard Time). Athena requires explicit cast: `from_iso8601_timestamp(datetime)` — not `date_parse`.
3. **Multiple sensors per location** — `sensors_id` varies within a single `location_id` file for stations measuring multiple parameters. Each row is one parameter reading for one hour.
4. **Coordinate precision** — some `lon` values have floating-point noise (e.g., `105.79990000000001`). Normalise to 6 decimal places in staging.
5. **Name format** in archive is `{human_name}-{location_id}` (e.g., `"Chi cục Bảo vệ Môi trường-2131268"`). Use `location_id` as the join key to `dim_locations`, not the name string.

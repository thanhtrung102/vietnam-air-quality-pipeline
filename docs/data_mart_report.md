# Data Mart Report — Vietnam Air Quality Pipeline

**Pipeline:** `D:\vietnam-air-quality-pipeline\transform\`
**Database:** `openaq_mart` (Amazon Athena / AWS Glue Data Catalog)
**Transformation layer:** dbt-core 1.10.0 + dbt-athena-community
**Storage format:** Parquet (Snappy compression), partitioned daily on `measurement_date`
**Last full build:** 2026-04-07 (dbt build — 85 tests passing, 17 models)

---

## Table of Contents

1. [Architecture & Lineage](#1-architecture--lineage)
2. [Seed Reference Tables](#2-seed-reference-tables)
3. [Staging & Intermediate Layer](#3-staging--intermediate-layer)
4. [Mart Models — Detailed Specifications](#4-mart-models--detailed-specifications)
   - [mart_daily_air_quality](#41-mart_daily_air_quality)
   - [mart_daily_aqi](#42-mart_daily_aqi)
   - [mart_daily_weather](#43-mart_daily_weather)
   - [mart_aq_weather_daily](#44-mart_aq_weather_daily)
   - [mart_health_summary](#45-mart_health_summary)
   - [mart_annual_monthly_trend](#46-mart_annual_monthly_trend)
   - [mart_exceedance_stats](#47-mart_exceedance_stats)
   - [mart_diurnal_profile](#48-mart_diurnal_profile)
   - [mart_monthly_profile](#49-mart_monthly_profile)
   - [mart_pollutant_ratio](#410-mart_pollutant_ratio)
   - [mart_lagged_features](#411-mart_lagged_features)
   - [mart_feature_stats](#412-mart_feature_stats)
   - [mart_forecast_accuracy](#413-mart_forecast_accuracy)
5. [Cross-Mart Summary](#5-cross-mart-summary)
6. [Design Patterns & Engineering Decisions](#6-design-patterns--engineering-decisions)
7. [Data Quality Controls](#7-data-quality-controls)
8. [QuickSight Dashboard Mapping](#8-quicksight-dashboard-mapping)

---

## 1. Architecture & Lineage

### Full DAG

```
                          ┌─────────────────┐
                          │  Raw S3 Layers   │
                          │  raw/batch/      │
                          │  raw/stream/     │
                          │  raw/weather/    │
                          └────────┬────────┘
                                   │
              ┌────────────────────┼────────────────────┐
              │                    │                    │
     ┌────────▼────────┐  ┌────────▼────────┐  ┌────────▼────────┐
     │ stg_measurements│  │  stg_weather    │  │   vn_stations   │
     │    (VIEW)       │  │    (VIEW)       │  │  (seed, TABLE)  │
     └────────┬────────┘  └────────┬────────┘  └────────┬────────┘
              │                    │                     │
     ┌────────▼────────┐  ┌────────▼────────┐           │
     │ int_measurements│  │ int_weather     │           │
     │   _enriched     │  │  _enriched      │           │
     │   (TABLE)       │  │   (TABLE)       │           │
     └────┬────────────┘  └────────┬────────┘           │
          │                        │                    │
          │  ┌─────────────────────┘                    │
          │  │                                          │
   ┌──────▼──▼──────────────────────────────────────────▼────────┐
   │                   mart_daily_air_quality                     │
   │        (TABLE, partitioned by measurement_date)              │
   └──┬──────────┬──────────┬──────────┬──────────┬──────────────┘
      │          │          │          │          │
      │    ┌─────▼──────┐   │   ┌──────▼─────┐   │
      │    │mart_daily  │   │   │mart_health │   │
      │    │   _aqi     │   │   │  _summary  │   │
      │    └────────────┘   │   └────────────┘   │
      │                     │                    │
      │              ┌──────▼───────┐    ┌───────▼──────────┐
      │              │mart_annual   │    │ mart_exceedance  │
      │              │_monthly_trend│    │    _stats        │
      │              └──────────────┘    └──────────────────┘
      │
      │   ┌─────────────────────────────────────────────────┐
      │   │              mart_pollutant_ratio               │
      │   └─────────────────────────────────────────────────┘
      │
      │   ┌────────────────────────────┐
      │   │     mart_daily_weather     │
      │   │  (from int_weather_enriched│
      │   └────────────┬───────────────┘
      │                │
      └────────────────▼─────────────────────────────────────┐
                ┌──────────────────────────────┐             │
                │     mart_aq_weather_daily    │             │
                └──────────────┬───────────────┘             │
                               │                             │
                   ┌───────────▼────────────┐                │
                   │  mart_lagged_features   │◄──── vn_holidays seed
                   └───────────┬────────────┘
                               │
                   ┌───────────▼────────────┐
                   │   mart_feature_stats    │
                   └────────────────────────┘

int_measurements_enriched ──────────────► mart_diurnal_profile
                          └─────────────► mart_monthly_profile

openaq_mart.mart_daily_forecast (Lambda-managed, external)
                          └─────────────► mart_forecast_accuracy ◄── mart_daily_air_quality
```

### Materialization Strategy

| Layer | Materialization | Reason |
|-------|----------------|--------|
| Staging | VIEW | Zero storage cost; always reflects latest raw data |
| Intermediate | TABLE | Cached join result reused by multiple downstreams |
| Mart (daily grain) | TABLE + partition | Athena partition pruning → average 63.6 KB scan/query |
| Mart (summary grain) | TABLE (no partition) | Small result sets; full scan cost negligible |
| mart_daily_forecast | External Athena table | Written by Lambda, not dbt-managed |

---

## 2. Seed Reference Tables

### `vn_stations` (23 rows)

Master registry of all monitored stations. Referenced by `relationships` dbt tests across mart models.

| Column | Type | Description |
|--------|------|-------------|
| `location_id` | INTEGER | OpenAQ v3 location identifier (primary key) |
| `location_name` | VARCHAR | Station display name |
| `city` | VARCHAR | `Hanoi` or `Ho Chi Minh City` |
| `province` | VARCHAR | Administrative province |
| `station_lat` | DECIMAL | WGS-84 latitude |
| `station_lon` | DECIMAL | WGS-84 longitude |
| `sensor_type` | VARCHAR | `reference` (FEM instrument) or `low-cost sensor` (AirGradient PMS5003) |
| `is_outlier_station` | INTEGER | `1` for station 6273386 (VNUHCMUS Campus 1) — artefact readings excluded from city aggregations |
| `openaq_entity` | VARCHAR | Operating organisation |

**Coverage:** 17 Hanoi stations (14 MONRE reference + 3 AirGradient LCS), 6 HCMC stations (3 MONRE reference + 3 AirGradient LCS)

### `vn_holidays` (~50 rows per year, 2023–2026)

Vietnamese public holiday calendar with Tết period flag. Used by `mart_lagged_features` to encode holiday effects on PM2.5 (reduced traffic on national holidays; elevated biomass burning during Tết fireworks period).

| Column | Type | Description |
|--------|------|-------------|
| `holiday_date` | DATE | Calendar date |
| `holiday_name` | VARCHAR | Holiday name (e.g. "Tết Nguyên Đán", "Ngày Giải phóng") |
| `is_tet_period` | INTEGER | `1` for 7-day Tết window (fireworks → PM spike), `0` otherwise |

---

## 3. Staging & Intermediate Layer

### Staging Views (not materialized)

**`stg_measurements`** — Reads from both `raw/batch/` (CSV.GZ) and `raw/stream/` (NDJSON) Glue tables. Applies:
- Sentinel value filter: `avg_value != -999.0` (~3.8% of raw rows)
- Parameter scope filter: retains PM2.5, PM10, NO₂, O₃, CO, SO₂
- Column standardisation: `measured_at` TIMESTAMP, `measurement_value` DOUBLE

**`stg_weather`** — Reads from `raw/weather/` Glue table (ERA5 via Open-Meteo API). Parses NDJSON hourly records into typed columns.

### Intermediate Tables

**`int_measurements_enriched`** — JOIN of `stg_measurements` × `vn_stations` on `location_id`. Enriches each measurement with station metadata (city, province, coordinates, sensor_type, is_outlier_station). This is the primary source for all per-measurement mart models.

**`int_weather_enriched`** — JOIN of `stg_weather` × `vn_stations` on `location_id`. Enriches each ERA5 hourly record with station metadata.

---

## 4. Mart Models — Detailed Specifications

---

### 4.1 `mart_daily_air_quality`

**Purpose:** The foundational daily mart. Aggregates raw measurements to daily station × parameter grain, computes US EPA 2024 AQI, exceedance flags, bias correction, and health category. All downstream marts depend on this model directly or indirectly.

**Grain:** One row per `(measurement_date, location_id, parameter)`

**Partitioned by:** `measurement_date`

**Source:** `int_measurements_enriched`

**Column Reference**

| Column | Type | Description |
|--------|------|-------------|
| `measurement_date` | DATE | UTC calendar date (partition key) |
| `location_id` | INTEGER | Station identifier |
| `location_name` | VARCHAR | Station display name |
| `city` | VARCHAR | `Hanoi` or `Ho Chi Minh City` |
| `province` | VARCHAR | Administrative province |
| `station_lat` | DECIMAL | Station latitude (WGS-84) |
| `station_lon` | DECIMAL | Station longitude (WGS-84) |
| `sensor_type` | VARCHAR | `reference` or `low-cost sensor` |
| `parameter` | VARCHAR | Pollutant code: `pm25`, `pm10`, `no2`, `o3`, `co`, `so2` |
| `avg_value` | DECIMAL(18,4) | Daily mean concentration (µg/m³ for PM; ppb for gases) |
| `max_value` | DECIMAL(18,4) | Daily maximum concentration |
| `min_value` | DECIMAL(18,4) | Daily minimum concentration |
| `reading_count` | INTEGER | Number of hourly readings aggregated |
| `sensor_count` | INTEGER | Number of distinct sensor units contributing |
| `aqi_value` | INTEGER | US EPA 2024 piecewise-linear AQI (PM2.5 and PM10 only; NULL for gases) |
| `aqi_category` | VARCHAR | Health category: Good / Moderate / Unhealthy for Sensitive Groups / Unhealthy / Very Unhealthy / Hazardous |
| `exceeds_who_24h` | INTEGER | `1` if avg_value > 15 µg/m³ (WHO AQG 2021 24-hour guideline); PM2.5 only |
| `exceeds_qcvn` | INTEGER | `1` if avg_value > 50 µg/m³ (QCVN 05:2023 Vietnam national standard); PM2.5 only |
| `who_compliant_day` | INTEGER | `1` if avg_value ≤ 15 µg/m³; PM2.5 only |
| `cigarette_equivalent` | DECIMAL(10,2) | avg_value / 22.0 (Berkeley Earth; 1 cigarette ≈ 22 µg/m³/day PM2.5) |
| `is_outlier_station` | INTEGER | `1` for station 6273386 (VNUHCMUS); excluded from city aggregations |
| `corrected_pm25` | DECIMAL(18,4) | Bias-corrected PM2.5: raw ÷ 1.50 for low-cost sensors; raw for reference instruments; NULL for non-PM2.5 |

**AQI Computation (US EPA 2024)**

```
AQI = (AQI_hi - AQI_lo) / (BP_hi - BP_lo) × (C - BP_lo) + AQI_lo

PM2.5 breakpoints (24-hour, µg/m³):
  0.0 – 9.0   → AQI   0–50   (Good)
  9.1 – 35.4  → AQI  51–100  (Moderate)
  35.5 – 55.4 → AQI 101–150  (Unhealthy for Sensitive Groups)
  55.5 – 125.4→ AQI 151–200  (Unhealthy)
  125.5 – 225.4→ AQI 201–300 (Very Unhealthy)
  225.5 – 325.4→ AQI 301–400 (Hazardous)
  > 325.4     → AQI 400–500  (Hazardous — beyond scale)

PM10 breakpoints (24-hour, µg/m³):
  0–54    → AQI   0–50
  55–154  → AQI  51–100
  155–254 → AQI 101–150
  255–354 → AQI 151–200
  355–424 → AQI 201–300
  425–604 → AQI 301–500
```

**dbt Tests:** 85 total across all models; this model: unique([measurement_date, location_id, parameter]), not_null([measurement_date, city, parameter, location_id, avg_value, reading_count]), relationships(location_id → vn_stations)

---

### 4.2 `mart_daily_aqi`

**Purpose:** Collapses the per-pollutant daily mart to one composite AQI row per station per day. Powers the live Leaflet map (via `aqi_api` Lambda) and the AQI calendar heat map in dashboards.

**Grain:** One row per `(measurement_date, location_id)`

**Partitioned by:** `measurement_date`

**Source:** `mart_daily_air_quality` (PM2.5 and PM10 rows, `is_outlier_station = 0`)

**Column Reference**

| Column | Type | Description |
|--------|------|-------------|
| `measurement_date` | DATE | UTC calendar date (partition key) |
| `location_id` | INTEGER | Station identifier |
| `location_name` | VARCHAR | Station display name |
| `city` | VARCHAR | `Hanoi` or `Ho Chi Minh City` |
| `province` | VARCHAR | Administrative province |
| `station_lat` | DECIMAL | Station latitude |
| `station_lon` | DECIMAL | Station longitude |
| `sensor_type` | VARCHAR | `reference` or `low-cost sensor` |
| `composite_aqi` | INTEGER | MAX(aqi_value) across PM2.5 and PM10 — US EPA composite rule |
| `dominant_pollutant` | VARCHAR | Pollutant driving composite_aqi; PM2.5 wins ties (max_by with +0.5 tie-breaker) |
| `health_category` | VARCHAR | AQI health category corresponding to composite_aqi |
| `pm25_avg` | DECIMAL(18,4) | Daily mean PM2.5 (µg/m³); raw (not bias-corrected) |
| `cigarette_equivalent` | DECIMAL(10,2) | Cigarettes-per-day equivalent for PM2.5 |

**Composite AQI Rule:** US EPA defines composite AQI as the maximum sub-index across all computed pollutants. PM2.5 wins ties to ensure combustion events (which elevate PM2.5 more than PM10) are correctly attributed.

---

### 4.3 `mart_daily_weather`

**Purpose:** Daily summary of ERA5 meteorological reanalysis per station. Provides the covariate signal for PM2.5 forecasting and pollution source analysis.

**Grain:** One row per `(measurement_date, location_id)`

**Partitioned by:** `measurement_date`

**Source:** `int_weather_enriched` (hourly ERA5 records)

**Column Reference**

| Column | Type | Description |
|--------|------|-------------|
| `measurement_date` | DATE | UTC calendar date (partition key) |
| `location_id` | INTEGER | Station identifier |
| `location_name` | VARCHAR | Station display name |
| `city` | VARCHAR | `Hanoi` or `Ho Chi Minh City` |
| `province` | VARCHAR | Administrative province |
| `sensor_type` | VARCHAR | Station instrument type |
| `avg_temperature_2m` | DECIMAL | Mean temperature at 2 m height (°C) |
| `max_temperature_2m` | DECIMAL | Maximum temperature at 2 m (°C) |
| `min_temperature_2m` | DECIMAL | Minimum temperature at 2 m (°C) |
| `avg_rh_2m` | DECIMAL | Mean relative humidity at 2 m (%) |
| `max_rh_2m` | DECIMAL | Maximum relative humidity (%) |
| `min_rh_2m` | DECIMAL | Minimum relative humidity (%) |
| `avg_wind_speed` | DECIMAL | Mean wind speed at 10 m (m/s) |
| `avg_wind_dir` | DECIMAL | Mean wind direction at 10 m (degrees, simple average — not circular) |
| `calm_wind_hours` | INTEGER | Count of hours with wind_speed < 2.0 m/s (≤24) |
| `total_precipitation_mm` | DECIMAL | Daily accumulated precipitation (mm) |
| `avg_surface_pressure_hpa` | DECIMAL | Mean surface pressure (hPa) |
| `avg_boundary_layer_height_m` | DECIMAL | Mean atmospheric boundary layer height (m) |
| `min_boundary_layer_height_m` | DECIMAL | Minimum BLH — captures morning inversion peak |
| `reading_count_hours` | INTEGER | Number of hourly records (expected: 24) |
| `inversion_risk` | INTEGER | `1` if min_BLH < 500 m AND avg_wind_speed < 2.0 m/s — shallow boundary layer + calm conditions trap surface pollutants |
| `wet_scavenging` | INTEGER | `1` if total_precipitation_mm > 5.0 — precipitation removes PM2.5 via below-cloud scavenging (Xu et al. threshold) |

**Meteorological Notes:**
- **BLH < 500 m** is characteristic of early-morning nocturnal inversions over Hanoi in the NE monsoon season (Nov–Mar), coinciding with peak PM2.5 episodes
- **Wet scavenging threshold (5 mm):** Light drizzle (< 5 mm) has negligible scavenging effect; convective events (> 5 mm) measurably reduce PM2.5 the following day
- Wind direction averaging is arithmetic (not circular mean), introducing bias near 0°/360° — acceptable for general seasonality but not for directional source attribution

---

### 4.4 `mart_aq_weather_daily`

**Purpose:** Joined air quality × meteorology at station-day grain. The primary input to machine learning feature engineering and correlation analysis.

**Grain:** One row per `(measurement_date, location_id)` — PM2.5 only

**Partitioned by:** `measurement_date`

**Sources:** `mart_daily_air_quality` (PM2.5, `is_outlier_station = 0`) LEFT JOIN `mart_daily_weather`

**Join Key:** `location_id` AND `measurement_date`

**Column Reference**

| Column | Type | Source | Description |
|--------|------|--------|-------------|
| `measurement_date` | DATE | AQ | UTC calendar date (partition key) |
| `location_id` | INTEGER | AQ | Station identifier |
| `location_name` | VARCHAR | AQ | Station display name |
| `city` | VARCHAR | AQ | City |
| `province` | VARCHAR | AQ | Province |
| `sensor_type` | VARCHAR | AQ | Instrument type |
| `avg_pm25` | DECIMAL | AQ | Raw daily mean PM2.5 (µg/m³) |
| `max_pm25` | DECIMAL | AQ | Daily max PM2.5 |
| `corrected_pm25` | DECIMAL | AQ | Bias-corrected PM2.5 (÷ 1.50 for LCS) |
| `aqi_value` | INTEGER | AQ | PM2.5 sub-index AQI |
| `aqi_category` | VARCHAR | AQ | Health category |
| `exceeds_who_24h` | INTEGER | AQ | WHO exceedance flag |
| `exceeds_qcvn` | INTEGER | AQ | QCVN exceedance flag |
| `cigarette_equivalent` | DECIMAL | AQ | Cigarettes/day equivalent |
| `avg_temperature_2m` | DECIMAL | Weather | Temperature (°C) — NULL if weather Lambda failed |
| `max_temperature_2m` | DECIMAL | Weather | Max temperature |
| `min_temperature_2m` | DECIMAL | Weather | Min temperature |
| `avg_rh_2m` | DECIMAL | Weather | Mean relative humidity (%) |
| `avg_wind_speed` | DECIMAL | Weather | Wind speed (m/s) |
| `avg_wind_dir` | DECIMAL | Weather | Wind direction (°) |
| `calm_wind_hours` | INTEGER | Weather | Hours with wind < 2 m/s |
| `total_precipitation_mm` | DECIMAL | Weather | Daily precipitation (mm) |
| `avg_surface_pressure_hpa` | DECIMAL | Weather | Surface pressure (hPa) |
| `avg_boundary_layer_height_m` | DECIMAL | Weather | Mean BLH (m) |
| `min_boundary_layer_height_m` | DECIMAL | Weather | Min BLH (m) — inversion proxy |
| `inversion_risk` | INTEGER | Weather | Inversion flag |
| `wet_scavenging` | INTEGER | Weather | Precipitation scavenging flag |

**Left Join Rationale:** AQ records are preserved even when ERA5 data is unavailable (weather Lambda backfill lag, API downtime). Weather columns are NULL in these rows but the PM2.5 record remains available for analysis.

---

### 4.5 `mart_health_summary`

**Purpose:** Annual city-level health outcome summary. Answers "How many days in 2024 did Hanoi have hazardous air?" Powers the year-over-year stacked bar chart and KPI cards in dashboards.

**Grain:** One row per `(city, year)`

**Partitioned:** No

**Source:** `mart_daily_air_quality` (PM2.5, `is_outlier_station = 0`)

**City-Level Aggregation:** A `city_daily` CTE first collapses all stations within a city to a daily city-average PM2.5, preventing Hanoi's 16 stations from being counted 16× in totals.

**Column Reference**

| Column | Type | Description |
|--------|------|-------------|
| `city` | VARCHAR | `Hanoi` or `Ho Chi Minh City` |
| `province` | VARCHAR | Administrative province |
| `year` | INTEGER | Calendar year (2023, 2024, 2025) |
| `total_days` | INTEGER | Number of days with observations in that year |
| `good_days` | INTEGER | Days where city AQI was Good (PM2.5 ≤ 9 µg/m³) |
| `moderate_days` | INTEGER | Days where city AQI was Moderate (9.1–35.4 µg/m³) |
| `usg_days` | INTEGER | Days where AQI was Unhealthy for Sensitive Groups (35.5–55.4 µg/m³) |
| `unhealthy_days` | INTEGER | Days where AQI was Unhealthy (55.5–125.4 µg/m³) |
| `very_unhealthy_days` | INTEGER | Days where AQI was Very Unhealthy (125.5–225.4 µg/m³) |
| `hazardous_days` | INTEGER | Days where AQI was Hazardous (> 225.4 µg/m³) |
| `who_compliant_days` | INTEGER | Days where city PM2.5 ≤ 15 µg/m³ (WHO 24-hour AQG 2021) |
| `who_compliance_pct` | DECIMAL | (who_compliant_days / total_days) × 100 |
| `avg_pm25` | DECIMAL(5,1) | City annual mean PM2.5 (µg/m³), 1 decimal place |
| `avg_cigarette_equivalent` | DECIMAL(5,2) | Annual mean cigarettes/day equivalent |
| `max_pm25` | DECIMAL(5,1) | Annual maximum daily PM2.5 (worst day) |
| `risk_label` | VARCHAR | Summary risk label: `Low` (≥ 80% WHO compliant) / `Moderate` (50–79%) / `High` (20–49%) / `Extreme` (< 20%) |

**Key Results (from pipeline runs):**
- Hanoi 3-year mean PM2.5 ≈ 40 µg/m³ → risk_label = `Extreme` (WHO compliance ~2% of days)
- HCMC 3-year mean PM2.5 ≈ 21 µg/m³ → risk_label = `High` (WHO compliance ~37% of days)

---

### 4.6 `mart_annual_monthly_trend`

**Purpose:** Year-over-year calendar month comparison. Answers "Is January 2025 worse than January 2024?" Supports trend detection and monthly seasonality dashboards.

**Grain:** One row per `(city, year, month_of_year)`

**Partitioned:** No

**Source:** `mart_daily_air_quality` (PM2.5, `is_outlier_station = 0`)

**Note on uniqueness vs `mart_monthly_profile`:** This mart preserves the year dimension for YoY comparison; `mart_monthly_profile` averages across all years for climatological baseline.

**Column Reference**

| Column | Type | Description |
|--------|------|-------------|
| `city` | VARCHAR | City |
| `province` | VARCHAR | Province |
| `year` | INTEGER | Calendar year |
| `month_of_year` | INTEGER | Month number (1 = January, 12 = December) |
| `total_days` | INTEGER | Days with observations in that city-year-month cell |
| `avg_pm25` | DECIMAL(10,2) | Mean daily city PM2.5 that month (µg/m³) |
| `max_pm25` | DECIMAL(10,2) | Maximum daily city PM2.5 that month |
| `p95_pm25` | DECIMAL(10,2) | 95th percentile daily PM2.5 (approximate, via Athena APPROX_PERCENTILE) |
| `who_exceedance_rate` | DECIMAL(5,1) | % of days where city PM2.5 > 15 µg/m³ |
| `qcvn_exceedance_rate` | DECIMAL(5,1) | % of days where city PM2.5 > 50 µg/m³ |

**Interpretation guide:**
- NE monsoon months (Nov–Mar): avg_pm25 typically 50–80 µg/m³ for Hanoi, who_exceedance_rate approaching 100%
- SW monsoon months (Jun–Sep): avg_pm25 typically 15–25 µg/m³, qcvn_exceedance_rate near 0%

---

### 4.7 `mart_exceedance_stats`

**Purpose:** Monthly exceedance counts and rates per city and pollutant. Answers "How many days in November 2024 did Hanoi exceed the Vietnamese national standard?" Supports compliance reporting and trend dashboards.

**Grain:** One row per `(city, parameter, year, month_of_year)`

**Partitioned:** No

**Source:** `mart_daily_air_quality` (PM2.5 in practice; parameter column retained for extensibility)

**Column Reference**

| Column | Type | Description |
|--------|------|-------------|
| `city` | VARCHAR | City |
| `parameter` | VARCHAR | Pollutant code (currently `pm25`) |
| `year` | INTEGER | Calendar year |
| `month_of_year` | INTEGER | Month number (1–12) |
| `total_days` | INTEGER | Observation days in that cell |
| `who_exceedance_days` | INTEGER | Days with city PM2.5 > 15 µg/m³ (WHO guideline) |
| `qcvn_exceedance_days` | INTEGER | Days with city PM2.5 > 50 µg/m³ (QCVN 05:2023) |
| `who_exceedance_rate` | DECIMAL(5,1) | who_exceedance_days / total_days × 100 |
| `qcvn_exceedance_rate` | DECIMAL(5,1) | qcvn_exceedance_days / total_days × 100 |
| `avg_pm25` | DECIMAL(10,2) | Mean daily city PM2.5 that month |
| `p95_pm25` | DECIMAL(10,2) | 95th percentile daily PM2.5 |

**Relationship to `mart_annual_monthly_trend`:** Overlapping coverage on the exceedance rate metrics. The key difference is that `mart_exceedance_stats` includes the `parameter` column and exposes raw day counts (not just rates), making it better suited for compliance-style reporting. `mart_annual_monthly_trend` additionally includes `max_pm25` and is the preferred source for trend line charts.

---

### 4.8 `mart_diurnal_profile`

**Purpose:** Hour-of-day average concentrations broken down by weekday/weekend and monsoon season. Answers "At what time of day does PM2.5 peak in Hanoi during the NE monsoon, and is the pattern different on weekdays vs weekends?"

**Grain:** One row per `(location_id, parameter, hour_of_day, day_type, season)`

**Partitioned:** No

**Source:** `int_measurements_enriched` (raw hourly measurements — pre-daily-aggregation)

**Time Zone:** UTC+7 (Vietnam Standard Time, no DST). Applied via `HOUR(measured_at + INTERVAL '7' HOUR)`.

**Column Reference**

| Column | Type | Description |
|--------|------|-------------|
| `location_id` | INTEGER | Station identifier |
| `location_name` | VARCHAR | Station display name |
| `city` | VARCHAR | City |
| `province` | VARCHAR | Province |
| `sensor_type` | VARCHAR | Instrument type |
| `parameter` | VARCHAR | Pollutant code |
| `hour_of_day` | INTEGER | Local hour (0–23, UTC+7) |
| `day_type` | VARCHAR | `Weekday` or `Weekend` |
| `season` | VARCHAR | Vietnam meteorological season (see below) |
| `avg_value` | DECIMAL(18,4) | Mean concentration at this hour/day_type/season combination |
| `max_value` | DECIMAL(18,4) | Maximum recorded concentration in this segment |
| `min_value` | DECIMAL(18,4) | Minimum recorded concentration |
| `reading_count` | INTEGER | Number of hourly readings aggregated |

**Season Definitions:**
| Season | Months | Meteorological Character |
|--------|--------|--------------------------|
| NE Monsoon (Nov–Mar) | Nov, Dec, Jan, Feb, Mar | Dominant, worst air quality; anticyclonic flow brings long-range transport from China; temperature inversions common |
| Transition (Apr–May) | Apr, May | Rice straw burning season (Red River Delta); PM2.5 spikes |
| SW Monsoon (Jun–Sep) | Jun, Jul, Aug, Sep | Best air quality; high BLH, convective mixing, frequent rainfall |
| Transition (Oct) | Oct | NE monsoon onset; improving quality from Aug/Sep trough |

**Key Diurnal Patterns:**
- **Hanoi NE monsoon weekday:** Peak 06:00–08:00 local (pre-dawn inversion + morning rush hour traffic); secondary 21:00–23:00 (nocturnal cooling)
- **HCMC:** Peak 08:00–10:00 local (later rush hour accumulation); less pronounced inversion signal due to tropical boundary layer dynamics

---

### 4.9 `mart_monthly_profile`

**Purpose:** Multi-year climatological monthly baseline per station. Unlike `mart_annual_monthly_trend`, this averages across all observed years to produce a single seasonal profile suitable for climatological comparisons.

**Grain:** One row per `(location_id, parameter, month_of_year)`

**Partitioned:** No

**Source:** `int_measurements_enriched` (raw measurements, all years)

**Column Reference**

| Column | Type | Description |
|--------|------|-------------|
| `location_id` | INTEGER | Station identifier |
| `location_name` | VARCHAR | Station display name |
| `city` | VARCHAR | City |
| `province` | VARCHAR | Province |
| `sensor_type` | VARCHAR | Instrument type |
| `parameter` | VARCHAR | Pollutant code |
| `month_of_year` | INTEGER | Month number (1–12) |
| `season` | VARCHAR | Vietnam meteorological season |
| `avg_value` | DECIMAL(18,4) | Multi-year mean concentration for that month across all years |
| `max_value` | DECIMAL(18,4) | All-time maximum for that month (across all years and days) |
| `min_value` | DECIMAL(18,4) | All-time minimum for that month |
| `p95_value` | DECIMAL(18,4) | 95th percentile (approximate) |
| `reading_count` | INTEGER | Total hourly readings aggregated across all occurrences of this month |
| `day_count` | INTEGER | Number of distinct calendar dates (measures data coverage completeness) |

**Use case distinction:**
- Use `mart_monthly_profile` for plotting a "typical year" seasonal curve (one value per month, station)
- Use `mart_annual_monthly_trend` for detecting interannual trends (multiple values per month, one per year)

---

### 4.10 `mart_pollutant_ratio`

**Purpose:** Daily PM2.5/PM10 ratio analysis for pollution source attribution. A high PM2.5/PM10 ratio indicates combustion-dominated sources (traffic exhaust, biomass burning); a low ratio indicates resuspended crustal dust (road dust, construction, soil).

**Grain:** One row per `(location_id, measurement_date)`

**Partitioned:** No

**Source:** `mart_daily_air_quality` (PM2.5 and PM10 rows, `is_outlier_station = 0`)

**Column Reference**

| Column | Type | Description |
|--------|------|-------------|
| `location_id` | INTEGER | Station identifier |
| `location_name` | VARCHAR | Station display name |
| `city` | VARCHAR | City |
| `province` | VARCHAR | Province |
| `measurement_date` | DATE | UTC calendar date |
| `pm25_avg` | DECIMAL(18,4) | Daily mean PM2.5 (µg/m³); NULL if no PM2.5 observation that day |
| `pm10_avg` | DECIMAL(18,4) | Daily mean PM10 (µg/m³); NULL if no PM10 observation |
| `pm25_pm10_ratio` | DECIMAL(18,4) | PM2.5 ÷ PM10; NULL if either pollutant missing or PM10 = 0 |
| `source_indicator` | VARCHAR | Source attribution: `combustion-dominated` / `mixed` / `crustal/dust` / NULL |

**Source Attribution Thresholds:**
| Ratio | Label | Interpretation |
|-------|-------|----------------|
| > 0.70 | `combustion-dominated` | Traffic exhaust, biomass burning — fine particles dominate |
| 0.40–0.70 | `mixed` | Combination of combustion + mechanical dust |
| < 0.40 | `crustal/dust` | Road dust, construction debris, soil resuspension |

**Validation observations:**
- Hanoi NE monsoon (Jan–Mar): ratio ≈ 0.68–0.74 → `combustion-dominated` (consistent with traffic + coal heating emissions)
- Hanoi SW monsoon (Jun–Sep): ratio ≈ 0.52–0.60 → `mixed` (construction activity, lower combustion)
- HCMC: persistently `mixed` (0.48–0.62); lower ratios may reflect higher road dust due to drier subtropical climate

---

### 4.11 `mart_lagged_features`

**Purpose:** Machine learning feature table for the SARIMA and Prophet forecast models. Provides autoregressive lags, rolling means, meteorological covariates, cyclical calendar encodings, and holiday flags. The forecast_generate Lambda reads this table to construct model inputs.

**Grain:** One row per `(location_id, measurement_date)` — PM2.5 only, `is_outlier_station = 0`

**Partitioned by:** `measurement_date`

**Sources:**
- `mart_aq_weather_daily` (PM2.5 + ERA5 weather)
- `vn_holidays` seed (holiday calendar)

**Column Reference**

| Column | Type | Description |
|--------|------|-------------|
| `measurement_date` | DATE | UTC calendar date (partition key) |
| `location_id` | INTEGER | Station identifier |
| `location_name` | VARCHAR | Station display name |
| `city` | VARCHAR | City |
| `province` | VARCHAR | Province |
| `sensor_type` | VARCHAR | Instrument type |
| `avg_pm25` | DECIMAL | Raw daily PM2.5 (µg/m³) |
| `corrected_pm25` | DECIMAL | Bias-corrected PM2.5 |
| `pm25_lag1` | DECIMAL | PM2.5 one day prior (NULL for first row of each station) |
| `pm25_lag7` | DECIMAL | PM2.5 seven days prior (NULL for first 7 rows) |
| `pm25_lag30` | DECIMAL | PM2.5 thirty days prior (NULL for first 30 rows) |
| `pm25_roll7` | DECIMAL | 7-day trailing mean (days t-6 to t) |
| `pm25_roll30` | DECIMAL | 30-day trailing mean (days t-29 to t) |
| `month_sin` | DOUBLE | SIN(2π × month / 12) — cyclical month encoding, avoids Dec/Jan discontinuity |
| `month_cos` | DOUBLE | COS(2π × month / 12) — orthogonal seasonality component |
| `day_of_week` | INTEGER | Day of week (1=Monday, 7=Sunday; Presto convention) |
| `is_weekend` | INTEGER | `1` if day_of_week IN (6, 7) |
| `is_holiday` | INTEGER | `1` if measurement_date is a Vietnamese public holiday |
| `is_tet_period` | INTEGER | `1` for 7-day Tết window (fireworks → acute PM2.5 spike) |
| `avg_rh_2m` | DECIMAL | ERA5 mean relative humidity (%) — NULL if weather unavailable |
| `avg_wind_speed` | DECIMAL | ERA5 mean wind speed (m/s) |
| `total_precipitation_mm` | DECIMAL | ERA5 daily precipitation (mm) |
| `inversion_risk` | INTEGER | Temperature inversion flag (0/1) |
| `wet_scavenging` | INTEGER | Precipitation scavenging flag (0/1) |
| `pm25_next1` | DECIMAL | NEXT day's PM2.5 — forecast target variable; NULL for final row of each station |

**Feature Engineering Notes:**
- **Cyclical encoding** (sin/cos): Raw month number (1–12) introduces a false discontinuity between December (12) and January (1). Encoding as sin/cos maps the 12-month cycle onto a continuous unit circle, preserving meteorological continuity across the new year.
- **Rolling means** are computed as trailing windows (days t-n+1 to t), not centered, to prevent data leakage.
- **Tết period:** Fireworks during the 7-day Lunar New Year celebration produce acute PM2.5 spikes independent of weather patterns; a separate flag is more interpretable than relying on the generic is_holiday flag.
- The SARIMA model trained on this table uses `pm25_lag1`, `pm25_roll7`, `month_sin/cos`, `avg_rh_2m`, `avg_wind_speed`, `inversion_risk` as exogenous regressors (SARIMAX variant).

---

### 4.12 `mart_feature_stats`

**Purpose:** Feature validation and data quality audit for the ML pipeline. Computes null counts, Pearson correlations, and descriptive statistics per station. Used during model development to select features and diagnose data gaps.

**Grain:** One row per `location_id` (station-level summary)

**Partitioned:** No

**Source:** `mart_lagged_features`

**Column Reference**

| Column | Type | Description |
|--------|------|-------------|
| `location_id` | INTEGER | Station identifier |
| `city` | VARCHAR | City |
| `location_name` | VARCHAR | Station display name |
| `total_rows` | INTEGER | Total observation days in the feature table for this station |
| `non_null_pm25` | INTEGER | Days with non-null avg_pm25 (should equal total_rows if staging filters correct) |
| `non_null_target` | INTEGER | Days with non-null pm25_next1 (total_rows − 1 expected for complete series) |
| `pm25_lag1_nulls` | INTEGER | Null count for pm25_lag1 (expected: 1 = first row only) |
| `pm25_lag7_nulls` | INTEGER | Null count for pm25_lag7 (expected: ≤ 7) |
| `pm25_lag30_nulls` | INTEGER | Null count for pm25_lag30 (expected: ≤ 30) |
| `pm25_roll7_nulls` | INTEGER | Null count for pm25_roll7 (< 6 if series starts with consecutive days) |
| `pm25_roll30_nulls` | INTEGER | Null count for pm25_roll30 |
| `rh_nulls` | INTEGER | Null count for avg_rh_2m (days where weather Lambda failed) |
| `wind_speed_nulls` | INTEGER | Null count for avg_wind_speed |
| `precip_nulls` | INTEGER | Null count for total_precipitation_mm |
| `inversion_risk_nulls` | INTEGER | Null count for inversion_risk |
| `corr_lag1_pm25` | DOUBLE | Pearson r(pm25_lag1, avg_pm25) — expected 0.70–0.90 (strong short-term autocorrelation) |
| `corr_lag7_pm25` | DOUBLE | Pearson r(pm25_lag7, avg_pm25) — expected 0.40–0.65 (weekly pattern) |
| `corr_lag30_pm25` | DOUBLE | Pearson r(pm25_lag30, avg_pm25) — expected 0.25–0.50 (seasonal persistence) |
| `corr_roll7_pm25` | DOUBLE | Pearson r(pm25_roll7, avg_pm25) — expected 0.80–0.95 (smoothed autocorr) |
| `corr_roll30_pm25` | DOUBLE | Pearson r(pm25_roll30, avg_pm25) |
| `corr_month_sin_pm25` | DOUBLE | Pearson r(month_sin, avg_pm25) — seasonal signal |
| `corr_month_cos_pm25` | DOUBLE | Pearson r(month_cos, avg_pm25) |
| `corr_dow_pm25` | DOUBLE | Pearson r(day_of_week, avg_pm25) — weekly traffic pattern |
| `corr_weekend_pm25` | DOUBLE | Pearson r(is_weekend, avg_pm25) |
| `corr_holiday_pm25` | DOUBLE | Pearson r(is_holiday, avg_pm25) |
| `corr_tet_pm25` | DOUBLE | Pearson r(is_tet_period, avg_pm25) |
| `corr_rh_pm25` | DOUBLE | Pearson r(avg_rh_2m, avg_pm25) — expected 0.20–0.45 (humidity traps hygroscopic aerosols) |
| `corr_wind_pm25` | DOUBLE | Pearson r(avg_wind_speed, avg_pm25) — expected −0.30 to −0.10 (dispersion) |
| `corr_precip_pm25` | DOUBLE | Pearson r(total_precipitation_mm, avg_pm25) — expected −0.25 to −0.05 (scavenging) |
| `corr_inv_pm25` | DOUBLE | Pearson r(inversion_risk, avg_pm25) — expected 0.15–0.35 |
| `corr_lag1_next` | DOUBLE | Pearson r(pm25_lag1, pm25_next1) — forecast-relevant lag-1 predictive power |
| `corr_roll7_next` | DOUBLE | Pearson r(pm25_roll7, pm25_next1) — rolling mean forecast relevance |
| `corr_rh_next` | DOUBLE | Pearson r(avg_rh_2m, pm25_next1) |
| `corr_wind_next` | DOUBLE | Pearson r(avg_wind_speed, pm25_next1) |
| `corr_precip_next` | DOUBLE | Pearson r(total_precipitation_mm, pm25_next1) |
| `corr_inv_next` | DOUBLE | Pearson r(inversion_risk, pm25_next1) |
| `mean_pm25` | DOUBLE | Station mean PM2.5 across full series |
| `median_pm25` | DOUBLE | Station median PM2.5 |
| `stddev_pm25` | DOUBLE | Standard deviation of daily PM2.5 |
| `min_pm25` | DOUBLE | Station minimum daily PM2.5 |
| `max_pm25` | DOUBLE | Station maximum daily PM2.5 |
| `series_start` | DATE | Earliest measurement_date for this station |
| `series_end` | DATE | Latest measurement_date for this station |

---

### 4.13 `mart_forecast_accuracy`

**Purpose:** Ongoing forecast evaluation. Joins SARIMA (and optionally Prophet) predictions against observed actuals, computing error metrics and rolling performance windows. CloudWatch alarm `ForecastRMSE` fires when rolling_rmse_30d > 25 µg/m³ for Hanoi stations.

**Grain:** One row per `(location_id, model, forecast_date)`

**Partitioned by:** `forecast_date`

**Sources:**
- `openaq_mart.mart_daily_forecast` — external Athena table written directly by the `forecast_generate` Lambda (Parquet, S3 prefix `processed/mart_daily_forecast/`)
- `mart_daily_air_quality` — for actual PM2.5 values (the "ground truth")

**Important:** `mart_daily_forecast` is NOT dbt-managed. It is written by the Lambda and registered in Glue separately. dbt models that reference it use a direct schema-qualified table name.

**Column Reference**

| Column | Type | Description |
|--------|------|-------------|
| `forecast_date` | DATE | The date being forecast (partition key) |
| `location_id` | INTEGER | Station identifier |
| `location_name` | VARCHAR | Station display name |
| `city` | VARCHAR | City |
| `model` | VARCHAR | Model name: `sarima` or `prophet` |
| `generated_at` | TIMESTAMP | When this forecast was produced (used for deduplication — latest run wins) |
| `forecast_pm25` | DECIMAL | Predicted PM2.5 (µg/m³) |
| `forecast_aqi` | INTEGER | Predicted AQI computed from forecast_pm25 |
| `forecast_aqi_category` | VARCHAR | Predicted health category |
| `ci_lower_95` | DECIMAL | 95% confidence interval lower bound |
| `ci_upper_95` | DECIMAL | 95% confidence interval upper bound |
| `holdout_rmse` | DECIMAL | RMSE on the 30-day holdout set used during this model run (static per run) |
| `actual_pm25` | DECIMAL | Observed PM2.5 on forecast_date (NULL if observation not yet available) |
| `error` | DECIMAL | forecast_pm25 − actual_pm25 (positive = over-forecast, negative = under-forecast); NULL until actual available |
| `abs_error` | DECIMAL | ABS(error) |
| `squared_error` | DECIMAL | error² |
| `rolling_rmse_7d` | DECIMAL | SQRT(AVG(squared_error)) over trailing 7 days for this station-model pair |
| `rolling_rmse_30d` | DECIMAL | SQRT(AVG(squared_error)) over trailing 30 days — **CloudWatch alarm threshold: 25 µg/m³** |
| `rolling_mae_30d` | DECIMAL | Mean absolute error over trailing 30 days |
| `rolling_bias_30d` | DECIMAL | Mean signed error over trailing 30 days (positive = systematic over-forecast) |

**Deduplication logic:** When the forecast Lambda reruns for a date (e.g., after a data gap), multiple rows exist for the same (location_id, model, forecast_date). The CTE uses `ROW_NUMBER() OVER (PARTITION BY location_id, model, forecast_date ORDER BY generated_at DESC)` and keeps only `rn = 1` — the most-recent forecast run.

**Current model performance (30-day holdout):**
- SARIMA Hanoi: RMSE ≈ 12.0 µg/m³
- SARIMA HCMC: RMSE ≈ 6.8 µg/m³
- Active forecast stations: 3 of 21 (stations with ≤ 90 days since last reading)

---

## 5. Cross-Mart Summary

| Model | Grain | Rows (est.) | Partition | Primary Use |
|-------|-------|------------|-----------|-------------|
| `mart_daily_air_quality` | date × station × parameter | ~450K | date | Foundation: AQI, exceedances, bias correction |
| `mart_daily_aqi` | date × station | ~75K | date | Live Leaflet map, AQI calendar |
| `mart_daily_weather` | date × station | ~75K | date | Weather aggregates, inversion/scavenging flags |
| `mart_aq_weather_daily` | date × station (PM2.5) | ~22K | date | AQ × weather join for ML |
| `mart_health_summary` | year × city | ~6 | — | Annual health KPIs, risk label |
| `mart_annual_monthly_trend` | year × month × city | ~72 | — | YoY seasonal comparison |
| `mart_exceedance_stats` | year × month × city × parameter | ~72 | — | Compliance reporting |
| `mart_diurnal_profile` | hour × day_type × season × station × parameter | ~20K | — | Hourly patterns |
| `mart_monthly_profile` | month × station × parameter | ~1.6K | — | Climatological baseline |
| `mart_pollutant_ratio` | date × station | ~22K | — | PM2.5/PM10 source attribution |
| `mart_lagged_features` | date × station (PM2.5) | ~22K | date | ML training inputs |
| `mart_feature_stats` | station | ~21 | — | ML feature QA |
| `mart_forecast_accuracy` | forecast_date × model × station | ~1.8K | forecast_date | Rolling RMSE, CloudWatch alarm |

**Total dbt models:** 17 (2 staging + 2 intermediate + 13 mart)  
**Total dbt tests:** 85 (PASS=85, WARN=0, ERROR=0 as of 2026-04-07)

---

## 6. Design Patterns & Engineering Decisions

### Multi-Station City Averaging

Hanoi has 16 monitoring stations; HCMC has up to 7. All city-level aggregations (`mart_health_summary`, `mart_annual_monthly_trend`, `mart_exceedance_stats`) use a `city_daily` CTE that first collapses stations to a single city-level daily average before computing annual statistics. Without this, Hanoi's values would be weighted 16× more than HCMC's in any unweighted COUNT or AVG.

```sql
-- city_daily CTE (shared pattern across 3 mart models)
SELECT city, province, measurement_date,
       ROUND(AVG(avg_value), 4) as pm25_city_avg
FROM mart_daily_air_quality
WHERE parameter = 'pm25' AND is_outlier_station = 0
GROUP BY city, province, measurement_date
```

### US EPA 2024 AQI vs Prior Breakpoints

The pipeline implements the **2024 revision** to the US EPA AQI breakpoints, which lowered the PM2.5 "Good" upper boundary from 12.0 to 9.0 µg/m³ and the "Moderate" upper boundary from 35.4 to 35.4 (unchanged) but redefined Good/Moderate thresholds. Using the 2024 breakpoints produces higher reported AQI values for the same concentration compared to the 2012 standard.

### Outlier Station Handling

Station 6273386 (VNUHCMUS Campus 1, Ho Chi Minh City) produced artefact PM2.5 readings reaching 2,000 µg/m³ during a sensor initialization event in March 2026. The flag `is_outlier_station = 1` is set in the `vn_stations` seed and propagated through `int_measurements_enriched` into every mart. All city-level aggregations filter `WHERE is_outlier_station = 0`. The station's data is still stored and queryable but excluded from health summaries, trend models, and forecasts.

### AirGradient Low-Cost Sensor Correction

AirGradient PMS5003 sensors overread PM2.5 by approximately +50% in tropical high-humidity environments (> 70% RH, typical of Vietnam year-round). The correction `corrected_pm25 = avg_value / 1.50` is applied in `mart_daily_air_quality` and propagated through all downstream models that use corrected values. The raw (uncorrected) `avg_value` is preserved for auditability. Sensor type is always exposed as a filter/grouping column so dashboard users can compare reference vs LCS readings.

### Partition Projection vs Crawlers

The Glue Data Catalog uses **partition projection** rather than Glue Crawlers for both raw and processed tables. Partition projection allows Athena to infer partition paths from column value ranges without scanning S3, eliminating Crawler latency and cost. Average Athena scan per query is 63.6 KB vs ~800 MB for a full table scan. At $5/TB, this reduces query cost from ~$0.004 to ~$0.0000003 per query.

### Left Join Preservation

`mart_aq_weather_daily` uses a LEFT JOIN (AQ left, weather right) to preserve AQ records even when ERA5 weather data is unavailable for that station-date. Weather data gaps occur when:
- The `weather_ingest` Lambda has not yet run (daily 02:00 UTC; AQ data may arrive before weather)
- Open-Meteo ERA5 API has temporary unavailability
- Historical backfill not yet complete for newly added stations

### Cyclical Month Encoding

`mart_lagged_features` encodes calendar month as sin/cos components to eliminate the artificial discontinuity between December (month=12) and January (month=1) that would otherwise confuse linear regression models. SIN and COS values map the 12-month cycle onto a continuous circle:

```
month_sin = SIN(2π × month / 12)   -- peaks at month 3 (March)
month_cos = COS(2π × month / 12)   -- peaks at month 1 (January)
```

### Deduplication in Forecast Accuracy

When the forecast Lambda reruns (due to a data gap or code update), it produces new rows for dates already in `mart_daily_forecast`. `mart_forecast_accuracy` uses `ROW_NUMBER() OVER (PARTITION BY location_id, model, forecast_date ORDER BY generated_at DESC)` to keep only the most recent forecast, ensuring monotonic improvement in error metrics is preserved.

---

## 7. Data Quality Controls

### Sentinel Value Filtering
- **Rule:** `avg_value != -999.0` applied in `stg_measurements`
- **Impact:** Removes ~3.8% of raw rows (OpenAQ uses -999 for missing/failed readings)

### Outlier Station Exclusion
- **Station:** 6273386 (VNUHCMUS Campus 1, HCMC)
- **Rule:** `is_outlier_station = 1` in vn_stations seed
- **Impact:** Excluded from all city aggregations; raw data retained for audit

### Low-Cost Sensor Bias Correction
- **Rule:** `corrected_pm25 = avg_value / 1.50` for sensor_type matching 'low-cost sensor'
- **Source:** AirGradient PMS5003 tropical humidity characterisation study

### dbt Test Coverage (85 tests total)

| Test Type | Count | What It Catches |
|-----------|-------|-----------------|
| `unique` / `unique_combination_of_columns` | ~15 | Duplicate rows (double-counting, join fan-out) |
| `not_null` | ~45 | Missing required fields |
| `relationships` | ~8 | Orphan station IDs not in vn_stations seed |
| `accepted_values` | ~17 | Invalid categories (e.g. unknown AQI categories, model names) |

### Known Limitations
- Wind direction averaging uses arithmetic mean rather than circular mean — biased near 0°/360° boundary
- SARIMA trained only on stations with ≤ 90-day data staleness (3 of 21 active stations as of 2026-04)
- ERA5 reanalysis: 5-day lag (ERA5T near-real-time) vs ERA5 final (3-month lag) — Open-Meteo uses ERA5T for recent dates
- PM10 data is sparse for some stations; `mart_pollutant_ratio` has high NULL rates for those stations

---

## 8. QuickSight Dashboard Mapping

| Dashboard Sheet | Primary Mart | Supporting Marts | Key Visuals |
|----------------|-------------|-----------------|-------------|
| **Sheet 1 — Historical Trends** | `mart_daily_aqi` | `mart_health_summary`, `mart_annual_monthly_trend`, `mart_daily_air_quality` | Annual AQI line by city; calendar heatmap (PM2.5 daily); health day stacked bar per year; PM2.5 time series with WHO/QCVN reference lines |
| **Sheet 2 — Seasonal & Diurnal** | `mart_monthly_profile` | `mart_diurnal_profile`, `mart_daily_air_quality` | Monthly PM2.5 bar chart; hour-of-day line (0–23 UTC+7); sensor type comparison; city KPI tiles |
| **Sheet 3 — Statistical Analysis** | `mart_exceedance_stats` | `mart_pollutant_ratio`, `mart_annual_monthly_trend` | WHO exceedance rate trend; PM2.5/PM10 ratio by season; YoY monthly comparison; corrected vs raw scatter |
| **Sheet 4 — Predictive Forecasts** | `mart_forecast_accuracy` | `mart_daily_forecast` (external) | 7-day SARIMA forecast with CI band; forecast vs actual scatter; rolling RMSE trend line (25 µg/m³ alarm threshold); forecast accuracy KPI |

All four datasets use **SPICE import mode** with a daily refresh at 04:00 UTC (after dbt completes at ~02:45 UTC via CodeBuild schedule). This eliminates per-query Athena cost for dashboard loads.

---

## 9. SQL Implementation Reference

The complete SQL for every mart model lives under `transform/models/marts/`. This section shows the actual source code for the most analytically significant models.

### 9.1 `mart_daily_air_quality` — AQI computation & exceedance flags

```sql
{{ config(
    materialized      = 'table',
    partitioned_by    = ['measurement_date'],
    format            = 'parquet',
    write_compression = 'snappy'
) }}

with source as (
    select * from {{ ref('int_measurements_enriched') }}
),

aggregated as (
    select
        city, province, parameter, location_id, location_name,
        station_lat, station_lon, sensor_type,
        round(avg(measurement_value), 4)  as avg_value,
        round(max(measurement_value), 4)  as max_value,
        round(min(measurement_value), 4)  as min_value,
        count(*)                          as reading_count,
        count(distinct sensor_id)         as sensor_count,
        measurement_date
    from source
    group by measurement_date, city, province, parameter,
             location_id, location_name, station_lat, station_lon, sensor_type
)

select
    city, province, parameter, location_id, location_name,
    station_lat, station_lon, sensor_type,
    avg_value, max_value, min_value, reading_count, sensor_count,

    -- US EPA 2024 AQI: piecewise linear interpolation
    -- AQI = ((I_HI - I_LO) / (BP_HI - BP_LO)) * (C - BP_LO) + I_LO
    case
        when parameter = 'pm25' then
            case
                when avg_value <=   9.0 then cast(round(( 50- 0)/( 9.0-0.0)*(avg_value-  0.0)+  0) as int)
                when avg_value <=  35.4 then cast(round((100-51)/(35.4-9.1)*(avg_value-  9.1)+ 51) as int)
                when avg_value <=  55.4 then cast(round((150-101)/(55.4-35.5)*(avg_value-35.5)+101) as int)
                when avg_value <= 125.4 then cast(round((200-151)/(125.4-55.5)*(avg_value-55.5)+151) as int)
                when avg_value <= 225.4 then cast(round((300-201)/(225.4-125.5)*(avg_value-125.5)+201) as int)
                when avg_value <= 325.4 then cast(round((500-301)/(325.4-225.5)*(avg_value-225.5)+301) as int)
                else 500
            end
        when parameter = 'pm10' then
            case
                when avg_value <=  54.0 then cast(round(( 50- 0)/( 54.0-0.0)*(avg_value-  0.0)+  0) as int)
                when avg_value <= 154.0 then cast(round((100-51)/(154.0-55.0)*(avg_value- 55.0)+ 51) as int)
                when avg_value <= 254.0 then cast(round((150-101)/(254.0-155.0)*(avg_value-155.0)+101) as int)
                when avg_value <= 354.0 then cast(round((200-151)/(354.0-255.0)*(avg_value-255.0)+151) as int)
                when avg_value <= 424.0 then cast(round((300-201)/(424.0-355.0)*(avg_value-355.0)+201) as int)
                when avg_value <= 604.0 then cast(round((500-301)/(604.0-425.0)*(avg_value-425.0)+301) as int)
                else 500
            end
        else null
    end as aqi_value,

    -- AQI category (re-derived from breakpoints — no self-reference to aqi_value alias)
    case
        when parameter not in ('pm25', 'pm10') then null
        when parameter = 'pm25' then
            case
                when avg_value <=   9.0 then 'Good'
                when avg_value <=  35.4 then 'Moderate'
                when avg_value <=  55.4 then 'Unhealthy for Sensitive Groups'
                when avg_value <= 125.4 then 'Unhealthy'
                when avg_value <= 225.4 then 'Very Unhealthy'
                else 'Hazardous'
            end
        when parameter = 'pm10' then
            case
                when avg_value <=  54.0 then 'Good'
                when avg_value <= 154.0 then 'Moderate'
                when avg_value <= 254.0 then 'Unhealthy for Sensitive Groups'
                when avg_value <= 354.0 then 'Unhealthy'
                when avg_value <= 424.0 then 'Very Unhealthy'
                else 'Hazardous'
            end
    end as aqi_category,

    -- Exceedance flags (PM2.5 only)
    case when parameter = 'pm25' then (avg_value > 15) end as exceeds_who_24h,
    case when parameter = 'pm25' then (avg_value > 50) end as exceeds_qcvn,
    case when parameter = 'pm25' then cast(avg_value <= 15 as int) end as who_compliant_day,
    case when parameter = 'pm25' then round(avg_value / 22.0, 2) end as cigarette_equivalent,

    -- Outlier station flag (station 6273386: sensor init artefact Mar 2026)
    case when location_id in (6273386) then 1 else 0 end as is_outlier_station,

    -- Bias-corrected PM2.5 (raw PMS5003 overestimates by ~50% in tropical humidity)
    case
        when parameter = 'pm25' then
            case
                when lower(sensor_type) like '%low%cost%'
                  or lower(sensor_type) = 'low-cost sensor'
                    then round(avg_value / 1.50, 4)
                else avg_value
            end
        else null
    end as corrected_pm25,

    measurement_date   -- partition column must be last

from aggregated
```

---

### 9.2 `mart_daily_aqi` — Composite AQI + dominant pollutant

Key pattern: the `max_by()` aggregate with a PM2.5 tie-breaker (+0.5) avoids a second self-join:

```sql
with per_pollutant as (
    select measurement_date, location_id, location_name, city, province,
           station_lat, station_lon, sensor_type, parameter,
           avg_value, aqi_value, aqi_category, cigarette_equivalent
    from {{ ref('mart_daily_air_quality') }}
    where aqi_value is not null and is_outlier_station = 0
),

composite as (
    select measurement_date, location_id, ...,
           max(aqi_value) as composite_aqi,
           max(case when parameter = 'pm25' then avg_value end) as pm25_avg,
           max(case when parameter = 'pm25' then cigarette_equivalent end) as cigarette_equivalent
    from per_pollutant
    group by measurement_date, location_id, ...
),

with_dominant as (
    select c.*,
           -- PM2.5 wins ties via +0.5 sort-key boost
           max_by(p.parameter,
               p.aqi_value + case when p.parameter = 'pm25' then 0.5 else 0 end
           ) as dominant_pollutant,
           max_by(p.aqi_category,
               p.aqi_value + case when p.parameter = 'pm25' then 0.5 else 0 end
           ) as health_category
    from composite c
    join per_pollutant p
        on c.measurement_date = p.measurement_date
        and c.location_id     = p.location_id
        and c.composite_aqi   = p.aqi_value
    group by c.measurement_date, c.location_id, ...
)

select city, province, location_id, ..., composite_aqi, dominant_pollutant,
       health_category, pm25_avg, cigarette_equivalent, measurement_date
from with_dominant
```

---

### 9.3 `mart_health_summary` — city_daily CTE (shared pattern)

This two-level aggregation is the canonical city-deduplication pattern reused across `mart_health_summary`, `mart_annual_monthly_trend`, and `mart_exceedance_stats`:

```sql
with city_daily as (
    -- Step 1: collapse all reference stations in a city to one city-level daily avg.
    -- Without this step Hanoi (16 stations) would count 16× more than HCMC (7 stations).
    select
        city, province, measurement_date,
        year(measurement_date)              as year,
        round(avg(avg_value), 4)            as pm25_city_avg,
        round(avg(avg_value) / 22.0, 2)     as cigarette_equivalent,
        cast(avg(avg_value) <= 15 as int)   as who_compliant_day,
        case
            when avg(avg_value) <=   9.0 then 'Good'
            when avg(avg_value) <=  35.4 then 'Moderate'
            when avg(avg_value) <=  55.4 then 'Unhealthy for Sensitive Groups'
            when avg(avg_value) <= 125.4 then 'Unhealthy'
            when avg(avg_value) <= 225.4 then 'Very Unhealthy'
            else 'Hazardous'
        end as aqi_category
    from {{ ref('mart_daily_air_quality') }}
    where parameter = 'pm25' and is_outlier_station = 0
    group by city, province, measurement_date
),

aggregated as (
    -- Step 2: aggregate city-level daily values into annual city stats
    select
        city, province, year,
        count(*)                                      as total_days,
        count_if(aqi_category = 'Good')               as good_days,
        count_if(aqi_category = 'Moderate')           as moderate_days,
        count_if(aqi_category = 'Unhealthy for Sensitive Groups') as usg_days,
        count_if(aqi_category = 'Unhealthy')          as unhealthy_days,
        count_if(aqi_category = 'Very Unhealthy')     as very_unhealthy_days,
        count_if(aqi_category = 'Hazardous')          as hazardous_days,
        count_if(who_compliant_day = 1)               as who_compliant_days,
        round(100.0 * count_if(who_compliant_day = 1) / count(*), 1) as who_compliance_pct,
        round(avg(pm25_city_avg), 1)                  as avg_pm25,
        round(avg(cigarette_equivalent), 2)           as avg_cigarette_equivalent,
        round(max(pm25_city_avg), 1)                  as max_pm25
    from city_daily
    group by city, province, year
)

select *, case
    when who_compliance_pct >= 80 then 'Low'
    when who_compliance_pct >= 50 then 'Moderate'
    when who_compliance_pct >= 20 then 'High'
    else 'Extreme'
end as risk_label
from aggregated
```

The same `city_daily` CTE (without the `year` and `aqi_category` columns) drives `mart_annual_monthly_trend`:

```sql
-- mart_annual_monthly_trend uses the same collapse, then groups by year × month
select city, province, year, month_of_year,
       count(*)                                                  as total_days,
       round(avg(pm25_city_avg), 2)                              as avg_pm25,
       round(max(pm25_city_avg), 2)                              as max_pm25,
       round(approx_percentile(pm25_city_avg, 0.95), 2)          as p95_pm25,
       round(100.0 * count_if(pm25_city_avg > 15) / count(*), 1) as who_exceedance_rate,
       round(100.0 * count_if(pm25_city_avg > 50) / count(*), 1) as qcvn_exceedance_rate
from city_daily
group by city, province, year, month_of_year
```

---

### 9.4 `mart_daily_weather` — ERA5 aggregation + derived flags

```sql
with daily as (
    select
        location_id, location_name, city, province, sensor_type,
        round(avg(temperature_2m), 4)          as avg_temperature_2m,
        round(max(temperature_2m), 4)          as max_temperature_2m,
        round(min(temperature_2m), 4)          as min_temperature_2m,
        round(avg(rh_2m), 2)                   as avg_rh_2m,
        round(max(rh_2m), 2)                   as max_rh_2m,
        round(min(rh_2m), 2)                   as min_rh_2m,
        round(avg(wind_speed), 4)              as avg_wind_speed,
        round(avg(wind_dir), 2)                as avg_wind_dir,  -- arithmetic, not circular
        count(case when wind_speed < 2.0 then 1 end) as calm_wind_hours,
        round(sum(precipitation_mm), 4)        as total_precipitation_mm,
        round(avg(surface_pressure_hpa), 2)    as avg_surface_pressure_hpa,
        round(avg(boundary_layer_height_m), 1) as avg_boundary_layer_height_m,
        round(min(boundary_layer_height_m), 1) as min_boundary_layer_height_m,
        count(*) as reading_count_hours,
        measurement_date
    from {{ ref('int_weather_enriched') }}
    group by measurement_date, location_id, location_name, city, province, sensor_type
)

select *,
    -- Inversion: shallow BLH traps surface emissions; calm winds prevent lateral dispersion
    cast(min_boundary_layer_height_m < 500.0 and avg_wind_speed < 2.0 as int) as inversion_risk,
    -- Wet scavenging: >5 mm/day removes surface PM2.5 via below-cloud washout (Xu et al., 2017)
    cast(total_precipitation_mm > 5.0 as int) as wet_scavenging,
    measurement_date
from daily
```

---

### 9.5 `mart_aq_weather_daily` — Left-preserving AQ × weather join

```sql
with aq as (
    select location_id, location_name, city, province, sensor_type,
           avg_value as avg_pm25, max_value as max_pm25, corrected_pm25,
           aqi_value, aqi_category, exceeds_who_24h, exceeds_qcvn,
           cigarette_equivalent, measurement_date
    from {{ ref('mart_daily_air_quality') }}
    where parameter = 'pm25' and is_outlier_station = 0
),

weather as (
    select location_id, measurement_date,
           avg_temperature_2m, max_temperature_2m, min_temperature_2m,
           avg_rh_2m, max_rh_2m, min_rh_2m, avg_wind_speed, avg_wind_dir,
           calm_wind_hours, total_precipitation_mm, avg_surface_pressure_hpa,
           avg_boundary_layer_height_m, min_boundary_layer_height_m,
           inversion_risk, wet_scavenging
    from {{ ref('mart_daily_weather') }}
)

-- LEFT JOIN: AQ record is preserved even when weather Lambda has not run.
-- All weather columns are NULL on unmatched dates.
select a.*, w.avg_temperature_2m, w.max_temperature_2m, w.min_temperature_2m,
       w.avg_rh_2m, w.max_rh_2m, w.min_rh_2m, w.avg_wind_speed, w.avg_wind_dir,
       w.calm_wind_hours, w.total_precipitation_mm, w.avg_surface_pressure_hpa,
       w.avg_boundary_layer_height_m, w.min_boundary_layer_height_m,
       w.inversion_risk, w.wet_scavenging
from aq a
left join weather w on a.location_id = w.location_id and a.measurement_date = w.measurement_date
```

---

### 9.6 `mart_diurnal_profile` — UTC→UTC+7 conversion + season labelling

```sql
{{ config(materialized = 'table', partitioned_by = [], ...) }}

with labelled as (
    select
        location_id, location_name, city, province, sensor_type, parameter,
        measurement_value,

        -- UTC → Vietnam local time (UTC+7, no DST ever observed in Vietnam)
        hour(measured_at + interval '7' hour) as hour_of_day,

        -- Weekday/weekend split: traffic rush-hour peaks (07–09, 17–19) are
        -- strongly attenuated on weekends
        case
            when day_of_week(date(measured_at + interval '7' hour)) in (6, 7)
                then 'Weekend'
            else 'Weekday'
        end as day_type,

        -- Vietnam meteorological seasons (boundary layer behaviour differs sharply)
        case
            when month(date(measured_at + interval '7' hour)) in (11,12,1,2,3)
                then 'NE Monsoon (Nov-Mar)'
            when month(date(measured_at + interval '7' hour)) in (4,5)
                then 'Transition (Apr-May)'
            when month(date(measured_at + interval '7' hour)) in (6,7,8,9)
                then 'SW Monsoon (Jun-Sep)'
            else 'Transition (Oct)'
        end as season

    from {{ ref('int_measurements_enriched') }}
)

select
    location_id, location_name, city, province, sensor_type,
    parameter, hour_of_day, day_type, season,
    round(avg(measurement_value), 4) as avg_value,
    round(max(measurement_value), 4) as max_value,
    round(min(measurement_value), 4) as min_value,
    count(*) as reading_count
from labelled
group by location_id, location_name, city, province, sensor_type,
         parameter, hour_of_day, day_type, season
```

---

### 9.7 `mart_pollutant_ratio` — Conditional aggregation pivot

```sql
{{ config(materialized = 'table', partitioned_by = [], ...) }}

select
    location_id, location_name, city, province, measurement_date,

    -- Pivot PM2.5 and PM10 from rows into columns — no JOIN needed
    round(max(case when parameter = 'pm25' then avg_value end), 4) as pm25_avg,
    round(max(case when parameter = 'pm10' then avg_value end), 4) as pm10_avg,

    -- Ratio: NULL when either pollutant absent or PM10 = 0
    case
        when max(case when parameter = 'pm25' then avg_value end) is null
          or max(case when parameter = 'pm10' then avg_value end) is null
          or max(case when parameter = 'pm10' then avg_value end) = 0
            then null
        else round(
            max(case when parameter = 'pm25' then avg_value end) /
            max(case when parameter = 'pm10' then avg_value end), 4
        )
    end as pm25_pm10_ratio,

    -- Source attribution (literature-validated thresholds)
    case
        when ... then null   -- null guard (same condition as above)
        when ratio > 0.7  then 'combustion-dominated'
        when ratio >= 0.4 then 'mixed'
        else 'crustal/dust'
    end as source_indicator

from {{ ref('mart_daily_air_quality') }}
where parameter in ('pm25', 'pm10') and is_outlier_station = 0
group by location_id, location_name, city, province, measurement_date
```

---

### 9.8 `mart_lagged_features` — Window functions for ML features

```sql
with aq_weather as (
    select location_id, ..., avg_pm25, corrected_pm25, measurement_date,
           avg_rh_2m, avg_wind_speed, total_precipitation_mm, inversion_risk, wet_scavenging
    from {{ ref('mart_aq_weather_daily') }}
    where avg_pm25 is not null
),

holidays as (
    select cast(date as date) as holiday_date, is_tet_period
    from {{ ref('vn_holidays') }}
),

windowed as (
    select *,
        -- 1. Autoregressive lags (PARTITION BY location_id prevents cross-station leakage)
        round(lag(avg_pm25, 1)  over (partition by location_id order by measurement_date), 4) as pm25_lag1,
        round(lag(avg_pm25, 7)  over (partition by location_id order by measurement_date), 4) as pm25_lag7,
        round(lag(avg_pm25, 30) over (partition by location_id order by measurement_date), 4) as pm25_lag30,

        -- 2. Trailing rolling means (ROWS BETWEEN avoids look-ahead bias)
        round(avg(avg_pm25) over (
            partition by location_id order by measurement_date
            rows between 6  preceding and current row), 4) as pm25_roll7,
        round(avg(avg_pm25) over (
            partition by location_id order by measurement_date
            rows between 29 preceding and current row), 4) as pm25_roll30,

        -- 3. Cyclical month encoding (avoids Dec→Jan discontinuity in linear models)
        round(sin(2.0 * pi() * month(measurement_date) / 12.0), 6) as month_sin,
        round(cos(2.0 * pi() * month(measurement_date) / 12.0), 6) as month_cos,

        -- 4. Calendar
        day_of_week(measurement_date) as day_of_week,
        cast(day_of_week(measurement_date) in (6, 7) as int) as is_weekend,

        -- 6. Supervised target: LEAD(1) is NULL for the last row of each series
        round(lead(avg_pm25, 1) over (partition by location_id order by measurement_date), 4) as pm25_next1

    from aq_weather
),

with_holidays as (
    select w.*,
           cast(h.holiday_date is not null as int) as is_holiday,
           coalesce(h.is_tet_period, 0)            as is_tet_period
    from windowed w
    left join holidays h on w.measurement_date = h.holiday_date
)

select * from with_holidays
```

---

### 9.9 `mart_forecast_accuracy` — Deduplication + rolling error windows

```sql
with latest_forecasts as (
    -- Most-recent-run forecast wins when Lambda reforecasts a date
    select *, row_number() over (
        partition by location_id, model, forecast_date
        order by generated_at desc
    ) as rn
    from openaq_mart.mart_daily_forecast   -- Lambda-managed external table
),

actuals as (
    select location_id, avg_value as actual_pm25, measurement_date
    from {{ ref('mart_daily_air_quality') }}
    where parameter = 'pm25' and is_outlier_station = 0
),

matched as (
    select f.*, a.actual_pm25,
           case when a.actual_pm25 is not null
                then round(f.forecast_pm25 - a.actual_pm25, 4) end as error,
           case when a.actual_pm25 is not null
                then round(abs(f.forecast_pm25 - a.actual_pm25), 4) end as abs_error,
           case when a.actual_pm25 is not null
                then round(power(f.forecast_pm25 - a.actual_pm25, 2), 4) end as squared_error
    from latest_forecasts f
    left join actuals a on f.location_id = a.location_id and f.forecast_date = a.measurement_date
    where f.rn = 1
)

select *,
    -- Rolling RMSE 7-day (CloudWatch alarm threshold: 25 µg/m³ for Hanoi SARIMA)
    round(sqrt(avg(squared_error) over (
        partition by location_id, model order by forecast_date
        rows between 6 preceding and current row)), 2) as rolling_rmse_7d,

    -- Rolling RMSE 30-day
    round(sqrt(avg(squared_error) over (
        partition by location_id, model order by forecast_date
        rows between 29 preceding and current row)), 2) as rolling_rmse_30d,

    round(avg(abs_error) over (... rows between 29 preceding and current row), 2) as rolling_mae_30d,
    round(avg(error)     over (... rows between 29 preceding and current row), 2) as rolling_bias_30d,

    forecast_date   -- partition key last

from matched
```

---

### 9.10 `mart_feature_stats` — Pearson correlations via `corr()`

```sql
select
    location_id, city, location_name,
    count(*) as total_rows, count(avg_pm25) as non_null_pm25, count(pm25_next1) as non_null_target,

    -- Null counts (expected: lag1=1, lag7=7, lag30=30)
    count(*) - count(pm25_lag1)  as pm25_lag1_nulls,
    count(*) - count(pm25_lag7)  as pm25_lag7_nulls,
    count(*) - count(pm25_lag30) as pm25_lag30_nulls,
    count(*) - count(avg_rh_2m)  as rh_nulls,

    -- Pearson correlations vs current-day PM2.5 (expected ranges in parentheses)
    round(corr(pm25_lag1,  avg_pm25), 4) as corr_lag1_pm25,    -- 0.70–0.90
    round(corr(pm25_lag7,  avg_pm25), 4) as corr_lag7_pm25,    -- 0.40–0.65
    round(corr(pm25_roll7, avg_pm25), 4) as corr_roll7_pm25,   -- 0.80–0.95
    round(corr(avg_rh_2m,  avg_pm25), 4) as corr_rh_pm25,      -- 0.20–0.45
    round(corr(avg_wind_speed, avg_pm25), 4) as corr_wind_pm25, -- -0.30 to -0.10
    round(corr(total_precipitation_mm, avg_pm25), 4) as corr_precip_pm25, -- -0.25 to -0.05
    round(corr(cast(inversion_risk as double), avg_pm25), 4) as corr_inv_pm25, -- 0.15–0.35
    round(corr(cast(is_tet_period as double), avg_pm25), 4) as corr_tet_pm25,

    -- Pearson correlations vs next-day PM2.5 (forecast target quality)
    round(corr(pm25_lag1,  pm25_next1), 4) as corr_lag1_next,
    round(corr(pm25_roll7, pm25_next1), 4) as corr_roll7_next,

    -- Descriptive stats
    round(avg(avg_pm25), 2)                    as mean_pm25,
    round(approx_percentile(avg_pm25, 0.5), 2) as median_pm25,
    round(stddev(avg_pm25), 2)                 as stddev_pm25,
    min(measurement_date) as series_start,
    max(measurement_date) as series_end

from {{ ref('mart_lagged_features') }}
group by location_id, city, location_name
order by city, location_id
```

---

## 10. dbt Configuration Reference

### Global defaults (`dbt_project.yml`)

```yaml
models:
  openaq_transform:
    staging:
      +materialized: view        # No storage cost; always reflects latest raw

    intermediate:
      +materialized: table       # Cached once per dbt run; reused by multiple marts

    marts:
      +materialized: table
      +partitioned_by: ["measurement_date"]     # Default — overridden per model
      +s3_data_dir: "s3://openaq-pipeline-thanhtrung102/processed/"
```

### Per-model overrides

| Model | `partitioned_by` | `format` | `write_compression` | Notes |
|-------|-----------------|----------|---------------------|-------|
| `mart_daily_air_quality` | `['measurement_date']` | parquet | snappy | Foundation; ~450K rows |
| `mart_daily_aqi` | `['measurement_date']` | parquet | snappy | ~75K rows |
| `mart_daily_weather` | `['measurement_date']` | parquet | snappy | ~75K rows |
| `mart_aq_weather_daily` | `['measurement_date']` | parquet | snappy | ~22K rows |
| `mart_lagged_features` | `['measurement_date']` | parquet | snappy | ML input; ~22K rows |
| `mart_forecast_accuracy` | `['forecast_date']` | parquet | snappy | Uses `forecast_date` not `measurement_date` |
| `mart_health_summary` | `[]` (no partition) | parquet | snappy | 6 rows total |
| `mart_annual_monthly_trend` | `[]` | parquet | snappy | ~72 rows |
| `mart_exceedance_stats` | `[]` | parquet | snappy | ~72 rows |
| `mart_monthly_profile` | `[]` | parquet | snappy | ~1.6K rows |
| `mart_diurnal_profile` | `[]` | parquet | snappy | ~20K rows |
| `mart_pollutant_ratio` | `[]` | parquet | snappy | ~22K rows |
| `mart_feature_stats` | `[]` | parquet | snappy | 21 rows |

**Why partition-less for summary models?** The models without a partition (`[]`) are small (< 1 MB uncompressed). Athena partition projection adds zero benefit when a full-table scan costs under $0.001. Partitioning summary tables would fragment them into hundreds of tiny files, actually degrading performance.

### dbt test coverage summary

| Model | Uniqueness test | not_null columns | relationships | accepted_values |
|-------|----------------|-----------------|---------------|-----------------|
| `mart_daily_air_quality` | (date, location_id, parameter) | date, city, parameter, location_id, avg_value, reading_count | location_id → vn_stations | — |
| `mart_daily_aqi` | (date, location_id) | date, location_id, city, composite_aqi, dominant_pollutant, health_category | location_id → vn_stations | — |
| `mart_daily_weather` | (location_id, date) | location_id, date, city | — | — |
| `mart_aq_weather_daily` | (location_id, date) | location_id, date, city | — | — |
| `mart_health_summary` | (city, year) | city, year, total_days, who_compliance_pct, risk_label | — | risk_label ∈ {Low, Moderate, High, Extreme} |
| `mart_annual_monthly_trend` | (city, year, month) | city, year, month, total_days | — | — |
| `mart_exceedance_stats` | (city, parameter, year, month) | city, parameter, year, month, total_days | — | — |
| `mart_diurnal_profile` | (location_id, parameter, hour, day_type, season) | location_id, city, parameter, hour, day_type, season, avg_value | location_id → vn_stations | day_type ∈ {Weekday, Weekend} |
| `mart_monthly_profile` | (location_id, parameter, month) | location_id, city, parameter, month, season, avg_value | location_id → vn_stations | — |
| `mart_pollutant_ratio` | (location_id, date) | location_id, date | — | — |
| `mart_lagged_features` | (location_id, date) | location_id, date, city | — | — |
| `mart_feature_stats` | — | location_id (+ unique) | — | — |
| `mart_forecast_accuracy` | (location_id, model, forecast_date) | location_id, forecast_date, model | — | model ∈ {sarima, prophet} |

**Total: 85 tests** (as of 2026-04-07 dbt build — all passing)

---

## 11. QuickSight SPICE Dataset Inventory

Phase 2 deployed 8 SPICE datasets and 8 refresh schedules to AWS account `703668403514` (ap-southeast-1). All datasets refresh daily at **04:00 UTC**.

| Terraform resource | Dataset ID | Mart table | SPICE refresh | Sheet |
|-------------------|-----------|-----------|--------------|-------|
| `aws_quicksight_data_set.daily_aqi` | `openaq-daily-aqi` | `mart_daily_aqi` | 04:00 UTC daily | 1 |
| `aws_quicksight_data_set.health_summary` | `openaq-health-summary` | `mart_health_summary` | 04:00 UTC daily | 1 |
| `aws_quicksight_data_set.annual_monthly_trend` | `openaq-annual-monthly-trend` | `mart_annual_monthly_trend` | 04:00 UTC daily | 1 & 3 |
| `aws_quicksight_data_set.monthly_profile` | `openaq-monthly-profile` | `mart_monthly_profile` | 04:00 UTC daily | 2 |
| `aws_quicksight_data_set.diurnal_profile` | `openaq-diurnal-profile` | `mart_diurnal_profile` | 04:00 UTC daily | 2 |
| `aws_quicksight_data_set.exceedance_stats` | `openaq-exceedance-stats` | `mart_exceedance_stats` | 04:00 UTC daily | 3 |
| `aws_quicksight_data_set.pollutant_ratio` | `openaq-pollutant-ratio` | `mart_pollutant_ratio` | 04:00 UTC daily | 3 |
| `aws_quicksight_data_set.forecast_accuracy` | `openaq-forecast-accuracy` | `mart_forecast_accuracy` | 04:00 UTC daily | 4 |

**Shared Athena data source:** `openaq-athena` → workgroup `openaq_workgroup`, database `openaq_mart`

**Data source ARN:** `arn:aws:quicksight:ap-southeast-1:703668403514:datasource/openaq-athena`

**Service role ARN:** `arn:aws:iam::703668403514:role/QuickSightServiceRole-openaq`

### Ingestion monitoring

```bash
# Check SPICE ingestion status for any dataset
aws quicksight list-ingestions \
  --aws-account-id 703668403514 \
  --data-set-id openaq-daily-aqi \
  --region ap-southeast-1 \
  --query 'Ingestions[0].{Status:IngestionStatus,RowsIngested:RowInfo.RowsIngested,StartTime:CreatedTime}'

# Trigger a manual SPICE refresh
aws quicksight create-ingestion \
  --aws-account-id 703668403514 \
  --data-set-id openaq-daily-aqi \
  --ingestion-id manual-$(date +%Y%m%d-%H%M%S) \
  --region ap-southeast-1
```

### Marts NOT in SPICE (available for direct Athena query)

The following marts are queryable via Athena but not yet added to a QuickSight SPICE dataset (Phase 3 analysis definition will reference them as needed):

| Mart | Reason not in SPICE | Planned use |
|------|---------------------|-------------|
| `mart_daily_air_quality` | Large (~450K rows); already covered by `mart_daily_aqi` for dashboard needs | Raw data export, ad-hoc correlation queries |
| `mart_daily_weather` | Covered by `mart_aq_weather_daily` (which is also not in SPICE) | Weather-only analysis |
| `mart_aq_weather_daily` | Covered by feature mart; too large for current dashboard scope | Phase 5 model validation |
| `mart_lagged_features` | Read by forecast Lambda directly; not a dashboard source | ML training input |
| `mart_feature_stats` | 21-row QA table; queried manually post-dbt-build | Feature engineering validation |

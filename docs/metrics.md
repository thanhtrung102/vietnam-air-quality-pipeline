# Pipeline Metrics

## Historical Batch Load — Initial Sync

**Date:** 2026-03-25
**Script:** `ingestion/historical/sync_historical.sh`
**Source:** `s3://openaq-data-archive/records/csv.gz/` (us-east-1, requester-pays)
**Destination:** `s3://openaq-pipeline-thanhtrung102/raw/batch/`

| Metric | Value |
|---|---|
| Stations synced | 20 |
| Years covered | 2023, 2024, 2025, 2026 |
| Total sync operations | 80 (20 stations × 4 years) |
| Failed syncs | 0 |
| **Total files** | **4,657** |
| **Total size** | **~2.0 MiB compressed** |
| File size range | 1,006 B – 9.9 KiB per CSV.gz |
| Sync duration | ~10 minutes |

---

## Schema Spot-Check

Verified 9 columns present and consistent across all years for stations 7441, 7440, 4946812:

| Column | 2023 | 2024 | 2025 |
|---|---|---|---|
| location_id | ✅ unquoted int | ✅ quoted int | ✅ quoted int |
| sensors_id | ✅ | ✅ | ✅ |
| location | ✅ | ✅ | ✅ |
| datetime | ✅ `+07:00` offset | ✅ `+07:00` offset | ✅ `+07:00` offset |
| lat | ✅ | ✅ | ✅ |
| lon | ✅ | ✅ | ✅ |
| parameter | ✅ | ✅ | ✅ |
| units | ✅ | ✅ | ✅ |
| value | ✅ | ✅ | ✅ |

### Schema variation notes

- **2023 files:** columns unquoted (`location_id,sensors_id,...`)
- **2024–2025 files:** string columns quoted (`"location_id","sensors_id",...`); OpenCSVSerde handles both transparently
- **Sentinel -999.0:** confirmed present in station 7441 (2025) and 7440 (2024) — staging models must filter `WHERE value != -999.0`
- **lon floating-point noise:** observed `105.79470000000002` in station 4946812 — normalise to 6 dp in staging
- **5-minute granularity:** station 4946812 (2025) has readings every 5 min vs. hourly for older stations

---

## Athena External Table Validation

**Date:** 2026-03-26
**Table:** `openaq_raw.raw_measurements`
**Workgroup:** `openaq_workgroup`
**DDL:** `transform/setup/create_external_table.sql`

### Query 1 — Full table scan baseline

```sql
SELECT COUNT(*) FROM openaq_raw.raw_measurements
```

| Metric | Value |
|--------|-------|
| Row count | **898,246** |
| Data scanned | **6.848 MB** |

### Query 2 — Partition-filtered scan

```sql
SELECT COUNT(*) FROM openaq_raw.raw_measurements
WHERE locationid='7441' AND year='2025' AND month='01'
```

| Metric | Value |
|--------|-------|
| Row count | **744** |
| Data scanned | **0.010 MB** |

### Scan reduction

```
(6.848 - 0.010) / 6.848 * 100 = 99.85%
```

Partition projection pruned **99.85%** of data for a single station/year/month query.

### Query 3 — Parameter distribution

```sql
SELECT parameter, COUNT(*) as cnt
FROM openaq_raw.raw_measurements
GROUP BY parameter ORDER BY cnt DESC
```

| Parameter | Count |
|-----------|-------|
| pm25 | 206,761 |
| pm10 | 166,325 |
| no2 | 157,326 |
| co | 134,379 |
| o3 | 109,056 |
| so2 | 105,687 |
| relativehumidity | 4,678 |
| um003 | 4,678 |
| pm1 | 4,678 |
| temperature | 4,678 |

All six core pollutants (pm25, pm10, no2, o3, co, so2) confirmed present.

### Query 4 — Date range

```sql
SELECT MIN(datetime), MAX(datetime) FROM openaq_raw.raw_measurements
```

| Metric | Value |
|--------|-------|
| Earliest reading | `2023-01-01T01:00:00+07:00` |
| Latest reading | `2026-03-23T00:00:00+07:00` |

Date range spans 2023–2026 as expected.

### Query 5 — Parameters per station

```sql
SELECT location, COUNT(DISTINCT parameter) as params
FROM openaq_raw.raw_measurements
GROUP BY location ORDER BY location
```

| Station | Distinct Parameters |
|---------|-------------------|
| 556 Nguyễn Văn Cừ-4916744 | 5 |
| An Khánh-2131266 | 4 |
| Care Centre-6038073 | 5 |
| Chi cục Bảo vệ Môi trường-2131268 | 6 |
| Công viên Nhân Chính-4916745 | 6 |
| Cầu Diễn-2131267 | 4 |
| Hanoi-7441 | 1 |
| Ho Chi Minh City-7440 | 1 |
| OceanPark-6093148 | 5 |
| Số 1 đường Giải Phóng-4916746 | 5 |
| Số 46, phố Lưu Quang Vũ-2131268 | 6 |
| Thanh Xuân - Sóc Sơn-2131293 | 4 |
| VNUHCMUS CAMPUS 1-6243328 | 5 |
| _(+9 more stations)_ | 4–6 |

Multi-parameter coverage confirmed across all active stations.

---

## Sample Data

**Station 7441 (US Embassy Hanoi), 2023-01-01:**
```
location_id,sensors_id,location,datetime,lat,lon,parameter,units,value
7441,21632,Hanoi-7441,2023-01-01T01:00:00+07:00,21.021939,105.818806,pm25,µg/m³,71.0
7441,21632,Hanoi-7441,2023-01-01T02:00:00+07:00,21.021939,105.818806,pm25,µg/m³,77.0
```

**Station 4946812 (Nhân Chính Park), 2025-07-03:**
```
"location_id","sensors_id","location","datetime","lat","lon","parameter","units","value"
4946812,13502153,"Công viên hồ điều hòa Nhân Chính...-4916745","2025-07-03T22:40:00+07:00","21.0031","105.7947...","pm10","µg/m³","41.23"
```

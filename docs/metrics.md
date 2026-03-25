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

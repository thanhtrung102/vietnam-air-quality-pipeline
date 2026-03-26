# Vietnam Air Quality Pipeline — Project Context

## AWS Configuration
- **Region:** ap-southeast-1
- **S3 bucket name:** openaq-pipeline-thanhtrung102
- **Athena workgroup:** openaq_workgroup
- **Glue database:** openaq_raw
- **Kinesis stream name:** openaq_stream

## S3 Prefixes
- **Historical batch:** `raw/batch/locationid={id}/year={year}/month={month}/`
- **Streaming:** `raw/stream/{year}/{month}/{day}/{hour}/`
- **Processed mart:** `processed/mart_daily_air_quality/`

## dbt
- **Project name:** openaq_transform
- **Adapter:** dbt-athena-community
- **Mart table partitions on:** measurement_date
- **Mart table clusters on:** parameter, location_id

## Naming Conventions
- All identifiers: snake_case
- All AWS resources prefixed with: `openaq_`

## OpenAQ
- **Public archive bucket:** openaq-data-archive (us-east-1)
- **Archive file naming:** `location-{location_id}-{YYYYMMDD}.csv.gz`
- **Archive schema columns (9):** location_id, sensors_id, location, datetime, lat, lon, parameter, units, value
- **datetime format:** ISO-8601 string with `+07:00` offset — cast with `from_iso8601_timestamp(datetime)` in Athena
- **Sentinel value:** `-999.0` means missing — always filter `WHERE value != -999.0` in staging
- **Vietnamese station IDs (19 confirmed in archive):**

| ID | City | Name | Active |
|----|------|------|--------|
| 7441 | Hanoi | US Embassy Hanoi | to 2025-04 |
| 2539 | Hanoi | US Diplomatic Post Hanoi (predecessor) | 2016 only |
| 1285357 | Hanoi | SPARTAN - Vietnam Acad. Sci. | to 2020-06 |
| 2161290 | Hanoi | An Khánh | to 2025-06 |
| 2161291 | Hanoi | Cầu Diễn | to 2024-12 |
| 2161292 | Hanoi | Số 46 Lưu Quang Vũ | **active** |
| 2161316 | Hanoi | Thành Công | to 2024-02 |
| 2161317 | Hanoi | Thanh Xuân - Sóc Sơn | to 2024-09 |
| 2161318 | Hanoi | Tứ Liên | to 2024-03 |
| 2161319 | Hanoi | Vân Đình | to 2025-02 |
| 2161320 | Hanoi | Vân Hà | to 2025-06 |
| 2161321 | Hanoi | Văn Quán | to 2024-04 |
| 2161323 | Hanoi | Xuân Mai | to 2025-03 |
| 4946812 | Hanoi | Công viên Nhân Chính | **active** |
| 4946813 | Hanoi | Số 1 Giải Phóng - Bạch Mai | **active** |
| 4946811 | Hanoi | 556 Nguyễn Văn Cừ | **active** (2025–) |
| 6123215 | Hanoi area | OceanPark (20.9933°N, 105.9441°E, Hanoi-adjacent) | **active** since 2025-11-08 |
| 7440 | Ho Chi Minh City | US Diplomatic Post HCMC | to 2025-03 |
| 2446 | Ho Chi Minh City | US Diplomatic Post HCMC (predecessor) | 2016 only |
| 6068138 | Ho Chi Minh City | Care Centre | to 2025-12 |
| 6273386 | Ho Chi Minh City | VNUHCMUS Campus 1 | **active** |

- See `docs/stations.md` for full details, data quality notes, and exclusion rationale

## IAM
- **Local dev user:** terraform-admin (pre-existing, not managed by Terraform)
- **Orchestration:** EventBridge Scheduler + Lambda (terraform/lambda.tf) — Kestra Docker not available on build machine
- **Lambda batch function:** openaq_batch_sync (900s timeout, daily at 01:00 UTC)
- **Lambda streaming function:** openaq_streaming_producer (120s timeout, every 30 minutes)
- **EventBridge schedule batch:** openaq_batch_daily
- **EventBridge schedule streaming:** openaq_streaming_30min

## Rules
- **Never hardcode API keys** — always read from environment variables

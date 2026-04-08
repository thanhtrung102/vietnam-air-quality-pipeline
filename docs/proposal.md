# Project Proposal — Vietnam Air Quality Pipeline

**A Serverless End-to-End Air Quality Analytics Pipeline on AWS**

---

## 1. Executive Summary | Tóm tắt

This project builds a fully serverless data pipeline that ingests PM2.5 and PM10 measurements from 21 OpenAQ monitoring stations across Hanoi and Ho Chi Minh City into an AWS data lakehouse, enriches them with Open-Meteo ERA5 meteorological reanalysis, and delivers a live Leaflet station map and four-sheet QuickSight analytical dashboard with 7-day SARIMA forecasts.

All infrastructure is provisioned as code with Terraform. There is no persistent compute — every workload runs as an on-demand Lambda function. The pipeline answers four operational questions about air quality trends, seasonal patterns, pollution sources, and forecast accuracy.

*[VI: Dự án xây dựng pipeline dữ liệu hoàn toàn serverless, nạp dữ liệu PM2.5 và PM10 từ 21 trạm giám sát OpenAQ ở Hà Nội và TP.HCM vào data lakehouse AWS, làm giàu bằng dữ liệu khí tượng ERA5, và cung cấp bản đồ Leaflet trực tiếp cùng bảng điều khiển phân tích QuickSight 4 trang với dự báo SARIMA 7 ngày.]*

---

## 2. Problem Statement | Vấn đề

### What is the problem? | Vấn đề là gì?

Vietnam ranks among the most air-polluted countries in Southeast Asia. Hanoi regularly records 24-hour PM2.5 averages exceeding 100 µg/m³ during the November–March northeast monsoon — six times the WHO 24-hour guideline of 15 µg/m³ and twice the Vietnamese national standard QCVN 05:2023 (50 µg/m³ 24-hour mean). Ho Chi Minh City shows a weaker but accelerating upward trend driven by rapid urbanisation.

Despite an open sensor network of 21 stations, no continuously-updating system synthesises historical trends, seasonal exceedance patterns, combustion-source attribution, and short-range forecasts into a single pipeline that residents and policymakers can act on.

*[VI: Mặc dù có mạng lưới 21 trạm cảm biến mở, không có hệ thống nào liên tục cập nhật tổng hợp xu hướng lịch sử, tỷ lệ vượt ngưỡng theo mùa, phân bổ nguồn ô nhiễm và dự báo ngắn hạn thành một pipeline duy nhất.]*

### The solution | Giải pháp

The pipeline answers four operational questions:

1. **Trend** — How has PM2.5 changed year-over-year in Hanoi and Ho Chi Minh City, and how often does it breach WHO and QCVN thresholds?
2. **Seasonality** — When is air quality worst — which months and hours of day, and how does the pattern differ between monsoon seasons?
3. **Source attribution** — What is driving the pollution — traffic combustion or resuspended road/soil dust — and does the source mix shift seasonally?
4. **Forecast** — What will PM2.5 be over the next seven days, and is the forecast model remaining accurate over time?

### Benefits and ROI | Lợi ích

- **Operational cost:** ~$1.61/month in production (no persistent servers, no data warehouse)
- **Data coverage:** ~900,000 hourly readings, 2023–present, 21 stations
- **Latency:** near-real-time dashboard (≤30 min lag via Kinesis); analytical dashboard updated daily
- **Reproducibility:** full environment reproduced with `terraform apply` in ~5 minutes

---

## 3. Solution Architecture | Kiến trúc giải pháp

### AWS Services Used | Dịch vụ AWS

| Service | Role |
|---------|------|
| **Amazon S3** | Data lake — `raw/batch/`, `raw/stream/`, `raw/weather/`, `processed/` prefixes |
| **AWS Glue Data Catalog** | Schema registry with partition projection — no Crawlers required |
| **Amazon Athena** | SQL query engine over S3; target for dbt transformation layer |
| **Amazon Kinesis Data Streams** | Real-time measurement buffer (ON_DEMAND capacity) |
| **Amazon Kinesis Firehose** | Buffered GZIP delivery from Kinesis to S3 |
| **AWS Lambda** | 5 functions: batch_sync, streaming_producer, weather_ingest, aqi_api, forecast_generate |
| **Amazon EventBridge Scheduler** | Triggers batch sync (daily 01:00 UTC) and streaming (every 30 min) |
| **Amazon SNS** | Email alerts for CloudWatch alarms |
| **AWS Secrets Manager** | OPENAQ_API_KEY stored at runtime — not hardcoded in environment variables |
| **Amazon CloudWatch** | `ForecastRMSE` and `MissingStations` alarms with SNS notification |

### Component Design | Thiết kế thành phần

```
OpenAQ S3 Archive ──────────────────────────────────────────────┐
  (CSV.GZ, requester-pays)                                       │
                              batch_sync Lambda (daily 01:00)    │
                              ↓                                  │
                         raw/batch/ ──┐                         │
                                      │                         │
OpenAQ REST API v3 ────────────────── ↓                        │
  (streaming_producer, every 30 min) │                         │
  → Kinesis → Firehose → raw/stream/ ─┤                        │
                                      │ Glue Catalog            │
Open-Meteo ERA5 ────────────────────  │ Partition Projection    │
  (weather_ingest, daily 02:00)       ↓                        │
  → raw/weather/ ─────────────── Athena ──→ dbt (14 marts) ───┘
                                                    ↓
                                         aqi_api Lambda
                                              ↓
                                    API Gateway ──→ Leaflet Map
                                    QuickSight SPICE ──→ 4 Sheets
```

Architecture diagram: [docs/architecture.drawio](architecture.drawio) (open in GitHub or diagrams.net)

---

## 4. Technical Implementation | Triển khai kỹ thuật

The project was built in four sequential phases:

| Phase | Scope | Output |
|-------|-------|--------|
| **0 — Infrastructure** | Terraform provisioning of S3, Glue, Athena, Kinesis, IAM, EventBridge | All base AWS resources live |
| **1 — Ingestion** | Historical batch sync + streaming producer + ERA5 weather backfill | ~900K rows in S3, queryable in Athena |
| **2 — Transformation** | dbt seed + full build (2 staging, 2 intermediate, 13 analytical mart models) | 14 total models; 53+ tests passing |
| **3 — Forecast & Dashboard** | SARIMA Lambda container + ECR push; Leaflet map + QuickSight sheets | 7-day forecast for 3 active stations; live map and 4-sheet dashboard |

---

## 5. Timeline & Milestones | Lịch trình

| Week | Dates | Milestone |
|------|-------|-----------|
| 1 | Jan 6–10, 2026 | AWS setup, OpenAQ data exploration, Terraform init |
| 2 | Jan 13–17 | S3 + Glue partition projection deployed; historical sync complete |
| 3 | Jan 20–24 | Streaming pipeline (Kinesis + Firehose + EventBridge) live |
| 4 | Jan 27–31 | dbt staging + intermediate models; US EPA 2024 AQI logic |
| 5 | Feb 3–7 | Mart layer — health summary, exceedance stats, diurnal profile |
| 6 | Feb 10–14 | Weather Lambda; ERA5 365-day backfill; weather marts |
| 7 | Feb 17–21 | Feature engineering (lagged features, cyclical encoding, Tết flag) |
| 8 | Feb 24–28 | SARIMA forecast Lambda; Docker build; ECR push; first forecast run |
| 9 | Mar 3–7 | AQI API Lambda; Leaflet map deployed; end-to-end test |
| 10 | Mar 10–14 | All 4 QuickSight sheets; completeness_check Lambda |
| 11 | Mar 17–21 | Security hardening: Secrets Manager, XSS escaping, CloudWatch alarms |
| 12 | Mar 24–28 | Code quality (ruff, dead code sweep); FCJ workshop documentation |

---

## 6. Budget Estimation | Ước tính chi phí

Monthly cost in production (ap-southeast-1 pricing, April 2026):

| Service | Usage | Monthly cost |
|---------|-------|-------------|
| Amazon S3 | ~50 GB storage + ~10K requests | ~$1.15 |
| Amazon Athena | ~50 queries × 63.6 KB average scan | ~$0.00 |
| AWS Lambda | 5 functions × daily invocations | ~$0.00 (Free Tier) |
| Amazon Kinesis ON_DEMAND | ~200 records/30 min × 48 × 30 | ~$0.01 |
| Amazon CloudWatch | 2 alarms + custom metrics | ~$0.30 |
| Amazon SNS | < 1,000 email notifications | $0.00 |
| Amazon ECR | 1 image ~1.5 GB | ~$0.15 |
| **Total** | | **~$1.61/month** |

Key cost driver is S3 storage. Athena queries are effectively free at this data volume due to Parquet compression and partition projection (average scan 63.6 KB per query vs $5/TB threshold).

---

## 7. Risk Assessment | Đánh giá rủi ro

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| OpenAQ archive staleness (12/21 stations stopped reporting in 2024–2025) | High | Medium | `MAX_STALENESS_DAYS=90` guard; forecast limited to 3 stations with ≤90-day lag |
| Low-cost sensor PM2.5 overread (~+50%) | High | Medium | `corrected_pm25 = avg_value / 1.50` applied at `mart_daily_air_quality`; sensor type visible in dashboard popup |
| ML library API breaks (e.g. cmdstanpy / Prophet) | Medium | High | Prophet removed; SARIMA via `statsmodels` only — stable API, no compiled Stan dependency |
| AWS cost overrun | Low | Medium | Athena workgroup 10 GB/query scan limit; S3 lifecycle rules expire stream data after 60 days and Athena results after 7 days |
| Outlier station artefact readings (station 6273386, up to 2,000 µg/m³) | Confirmed | High | `is_outlier_station = 1` flag in `vn_stations` seed; excluded from all city-level health aggregations |

---

## 8. Expected Outcomes | Kết quả kỳ vọng

### Delivered

| Output | Status | Evidence |
|--------|--------|---------|
| Leaflet station map with live AQI | ✅ Built | [docs/leaflet_map.png](leaflet_map.png) |
| QuickSight Sheet 1 — Historical Trends | ✅ Built | [docs/quicksight_sheet1.png](quicksight_sheet1.png) |
| QuickSight Sheet 2 — Seasonal & Diurnal | ✅ Built | [docs/quicksight_sheet2.png](quicksight_sheet2.png) |
| QuickSight Sheet 3 — Statistical Analysis | ✅ Built | [docs/quicksight_sheet3.png](quicksight_sheet3.png) |
| QuickSight Sheet 4 — Predictive Forecasts | ✅ Built | [docs/quicksight_sheet4.png](quicksight_sheet4.png) |
| 7-day SARIMA forecast (3 active stations) | ✅ Built | 21 rows/run; ~12 µg/m³ RMSE Hanoi |
| dbt test suite | ✅ 53+ tests passing | `dbt build` → PASS=53 WARN=0 ERROR=0 |
| Terraform IaC | ✅ Complete | `terraform apply` provisions all resources |

### Key findings

- Hanoi 3-year mean PM2.5: ~40 µg/m³ — WHO compliance rate ~2% of days
- HCMC 3-year mean PM2.5: ~21 µg/m³ — WHO compliance rate ~37% of days
- Hanoi NE monsoon PM2.5/PM10 ratio ~0.69 → combustion-dominated source
- Diurnal peaks: Hanoi 07:00 (pre-dawn inversion + rush hour); HCMC 09:00 (morning-rush accumulation)
- SARIMA 30-day holdout RMSE: ~12.0 µg/m³ Hanoi, ~6.8 µg/m³ HCMC

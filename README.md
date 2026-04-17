# Vietnam Air Quality Pipeline

**A Serverless End-to-End Air Quality Analytics Pipeline on AWS**

---

## Student Information | Thông tin thực tập sinh

| Field | Value |
|-------|-------|
| **Name** | [TODO: Full name] |
| **Phone** | [TODO: Phone number] |
| **Email** | [TODO: Email address] |
| **School** | [TODO: University name] |
| **Major** | [TODO: Major/Faculty] |
| **Company** | [TODO: Company name] |
| **Position** | Cloud Data Engineering Intern |
| **Duration** | January 6 – April 4, 2026 (12 weeks) |

---

## Project Overview | Tổng quan Dự án

This project builds a fully serverless data pipeline that ingests PM2.5 and PM10 air quality readings from 21 OpenAQ monitoring stations across Hanoi and Ho Chi Minh City into an AWS data lakehouse. The pipeline enriches raw measurements with Open-Meteo ERA5 meteorological reanalysis, runs a 17-model dbt transformation layer on Amazon Athena, and delivers a live Leaflet station map served via API Gateway with 7-day SARIMA forecasts.

All infrastructure is declared in Terraform — the entire environment can be torn down and rebuilt with two commands. There is no persistent compute: every workload runs as an on-demand AWS Lambda function or short-lived CodeBuild job at a total cost of ~$3.22/month.

*[VI: Dự án này xây dựng pipeline dữ liệu hoàn toàn serverless nạp dữ liệu chất lượng không khí PM2.5 và PM10 từ 21 trạm giám sát OpenAQ ở Hà Nội và TP.HCM vào AWS data lakehouse. Toàn bộ hạ tầng được khai báo trong Terraform — môi trường có thể tái tạo hoàn toàn với hai lệnh.]*

> Architecture diagram: [docs/architecture.drawio](docs/architecture.drawio) — open in [diagrams.net](https://app.diagrams.net)

---

## Workshop Sections | Các phần Workshop

| FCJ § | Section | Description |
|-------|---------|-------------|
| 1.2 | [Worklog](docs/worklog.md) | 12-week internship log with objectives, tasks, and achievements |
| 1.3 | [Proposal](docs/proposal.md) | Problem statement, architecture, timeline, budget, risks, outcomes |
| 1.4 | [Events Participated](docs/events.md) | Events attended during the internship with role and takeaways |
| 1.5 / 5.1 | [Introduction](docs/workshop/5.1-introduction.md) | What you will build, architecture overview, learning objectives |
| 1.5 / 5.2 | [Prerequisites](docs/workshop/5.2-prerequisites.md) | IAM permissions, tool installation, project setup |
| 1.5 / 5.3 | [Storage & Catalog Stack](docs/workshop/5.3-storage-catalog.md) | Terraform deploy, Glue partition projection, Athena workgroup |
| 1.5 / 5.4 | [Data Ingestion Pipeline](docs/workshop/5.4-ingestion.md) | Historical batch sync, streaming producer, weather backfill, validation |
| 1.5 / 5.5 | [Transformation, Forecast & Security](docs/workshop/5.5-transform-security.md) | dbt build, forecast Lambda container, IAM design, CloudWatch |
| 1.5 / 5.6 | [Cleanup](docs/workshop/5.6-cleanup.md) | Full resource teardown with verification checklist |
| 1.6 | [Self-evaluation](docs/self-evaluation.md) | Self-assessment across 8 professional criteria with reflection |
| 1.7 | [Sharing & Feedback](docs/feedback.md) | Program impressions, satisfaction level, and recommendations |

---

## Quick Start (Demo Run) | Khởi động nhanh

*[VI: Đã đáp ứng điều kiện tiên quyết ([Bước 5.2](docs/workshop/5.2-prerequisites.md))? Chạy toàn bộ pipeline theo thứ tự sau:]*

Prerequisites met ([Step 5.2](docs/workshop/5.2-prerequisites.md))? Run the full pipeline in order:

```bash
# 1. Provision all AWS infrastructure
cd terraform/ && terraform apply

# 2. Sync 3 years of historical OpenAQ data (10–20 min)
export S3_BUCKET_NAME="openaq-pipeline-yourname"
bash ingestion/historical/sync_historical.sh

# 3. Backfill 365 days of weather data
aws lambda invoke --function-name openaq_weather_ingest \
  --payload '{"backfill_days": 365}' --cli-binary-format raw-in-base64-out \
  /tmp/weather.json

# 4. Build all 17 dbt models (set S3 paths — profiles.yml reads these via env_var)
export S3_DATA_DIR="s3://$S3_BUCKET_NAME/processed/"
export S3_STAGING_DIR="s3://$S3_BUCKET_NAME/dbt-staging/"
export AWS_DEFAULT_REGION="ap-southeast-1"
cd transform/ && dbt seed --profiles-dir . && dbt build --full-refresh --profiles-dir .

# 5. Build and push forecast Lambda image, then wire it
cd lambda/forecast_generate/ && docker build -t openaq-forecast-generate .
# (push to ECR — see Step 5.5.2 for full commands)
cd terraform/ && terraform apply -var="forecast_lambda_image_uri=<ecr-uri>"

# 6. Run first forecast
aws lambda invoke --function-name openaq_forecast_generate \
  --payload '{}' --cli-binary-format raw-in-base64-out /tmp/forecast.json
cat /tmp/forecast.json
# {"generated_at": "2026-04-17", "stations_ok": 3, "errors": 0, "sarima_records": 21, "alert_count": 0}

# 7. Deploy dashboard (inject your API URL — the map will be blank without this)
AQI_API_URL=$(cd terraform && terraform output -raw aqi_api_url)
sed "s|YOUR_API_GATEWAY_URL|$AQI_API_URL|" dashboard/index.html \
  | aws s3 cp - s3://$S3_BUCKET_NAME/dashboard/index.html \
    --content-type text/html

# Open the dashboard in your browser:
terraform -chdir=terraform output -raw dashboard_url
# http://openaq-pipeline-yourname.s3-website-ap-southeast-1.amazonaws.com/dashboard/index.html
```

---

## Dashboard | Bảng điều khiển

### Leaflet Station Map

The live map is served from `dashboard/index.html` (S3 static site). It fetches GeoJSON from the `aqi_api` Lambda via API Gateway and renders colour-coded station markers using Leaflet.js.

Each marker popup shows: composite AQI, PM2.5 (µg/m³), dominant pollutant, cigarette equivalent, sensor type, and measurement date.

*[VI: Bản đồ trực tiếp được phục vụ từ `dashboard/index.html` (trang web tĩnh S3). Nó lấy GeoJSON từ Lambda `aqi_api` qua API Gateway và hiển thị các điểm đánh dấu trạm được tô màu theo danh mục AQI. Mỗi popup hiển thị: AQI tổng hợp, PM2.5 (µg/m³), chất ô nhiễm chính, tương đương thuốc lá, loại cảm biến và ngày đo lường.]*

---

## Key Results | Kết quả chính

*[VI: Kết quả đo lường thực tế từ pipeline sau 3 năm dữ liệu (2023–2026):]*

| Metric | Value |
|--------|-------|
| Raw rows ingested | ~900,000 hourly readings (2023–present) |
| Stations | 21 (17 Hanoi, 4 HCMC) |
| dbt models | 17 (2 staging, 2 intermediate, 13 mart) |
| dbt tests | 85 |
| Hanoi 3-year mean PM2.5 | ~40 µg/m³ (WHO guideline: 5 µg/m³ annual) |
| Hanoi WHO compliance | ~2% of days |
| HCMC WHO compliance | ~37% of days |
| Active forecast stations | 3 of 21 (≤90 days since last reading) |
| SARIMA RMSE — Hanoi | ~12.0 µg/m³ (30-day holdout) |
| SARIMA RMSE — HCMC | ~6.8 µg/m³ (30-day holdout) |
| Athena average scan per query | 63.6 KB (partition projection) |
| Infrastructure cost | ~$3.22/month (see 5.1 cost table for breakdown) |

---

## Tech Stack | Công nghệ sử dụng

*[VI: Toàn bộ stack công nghệ được sử dụng trong dự án, từ hạ tầng đến dashboard:]*

| Layer | Technology |
|-------|-----------|
| IaC | Terraform ≥ 1.5 |
| Storage | Amazon S3 (Parquet/Snappy processed; CSV.GZ + NDJSON raw) |
| Catalog | AWS Glue Data Catalog + Partition Projection |
| Query | Amazon Athena (`openaq_workgroup`, 10 GB scan limit) |
| Streaming | Amazon Kinesis Data Streams (ON_DEMAND) + Firehose (GZIP) |
| Secrets | AWS Secrets Manager (`openaq/api_key`) |
| Transform | dbt-core + dbt-athena-community 1.10.0 |
| Orchestration | AWS EventBridge Scheduler |
| Compute | AWS Lambda (Python 3.12) — 6 functions |
| Forecast | AWS Lambda container (ECR) — SARIMA(1,1,1)(1,0,1,7) via statsmodels |
| Weather | Open-Meteo ERA5 Archive API (free, no API key) |
| Dashboard | Leaflet.js (S3 static site, served via API Gateway) |
| Analytics | Amazon QuickSight — 4-sheet analysis, 9 DIRECT_QUERY datasets over `openaq_mart` |
| Alerts | Amazon SNS + Amazon CloudWatch (ForecastRMSE, MissingStations alarms) |

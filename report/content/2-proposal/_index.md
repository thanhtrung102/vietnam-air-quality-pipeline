+++
title = "Proposal"
weight = 2
chapter = false
pre = " <b> 2. </b> "
+++

## 1. Executive Summary

The **Vietnam Air Quality Pipeline** is a fully serverless data platform on AWS that turns raw,
station-level air-quality readings into an analysis-ready, health-oriented product: a live station map
with the current **US EPA 2024 AQI**, an analytics dashboard (health scorecard, seasonal/weather drivers,
WHO/QCVN compliance), and a **7-day PM2.5 forecast**. It is an **AWS First Cloud Journey (FCJ)**
portfolio project whose goal is dual — demonstrate production-grade serverless data-engineering on AWS,
using a real and meaningful narrative (Vietnamese PM2.5 analytics) as the vehicle. Everything is
reproducible from `terraform apply` and runs inside a **≈ $3–8/month** envelope.

## 2. Problem Statement

### 2.1 Current Problem

Vietnam — especially Hanoi — has some of the highest PM2.5 levels in Southeast Asia, regularly exceeding
the WHO 24-hour guideline (15 µg/m³) and the national QCVN 05:2023 standard. Public air-quality data for
Vietnamese stations exists (OpenAQ), but it is **raw, station-level, and not analysis-ready**: there is
no consolidated, health-oriented view that combines pollutant readings with meteorology, applies the
current US EPA AQI methodology, tracks compliance over time, or forecasts the coming week.

### 2.2 Solution

A serverless AWS pipeline ingests historical **and** near-real-time air-quality data plus ERA5 weather
covariates, catalogs it on an S3 data lake (Glue partition projection), transforms it with **dbt-on-Athena**
into tested marts using the EPA-2024 AQI breakpoints, and serves a live map + analytics dashboard and a
SARIMA forecast. There are no servers to manage: **EventBridge Scheduler** drives every job and the stack
scales to zero between runs.

### 2.3 Benefits and Value

- **Health-oriented insight**, not raw numbers: AQI categories, cigarette-equivalent framing, and
  WHO/QCVN compliance over time.
- **Reproducible & portable**: one `terraform apply` rebuilds the whole stack from a clean clone.
- **Cost-efficient**: ≈ $3.22/month, guarded by a 10 GB Athena scan cap, scale-to-zero serverless, and an
  AWS Budget at $8.
- **Demonstrates competency** across the full AWS data lifecycle (ingest → catalog → transform → serve →
  forecast → observe), which is the FCJ review objective.

## 3. Solution Architecture

Three parallel ingestion paths converge on an S3 data lake, are cataloged by Glue (partition projection),
transformed by **dbt-on-Athena** (run by CodeBuild), and served through an API + static dashboard, with a
container-Lambda SARIMA forecaster. *(Facts audited against live AWS; the AWS-icon diagram is generated
from `docs/architecture_diagram.py` via mingrammer **diagrams** + Graphviz, regenerated in CI on deploy.)*

**Figure 1 — Cloud architecture (infrastructure & runtime).** Numbered steps trace the happy path:
① ingest → ② land in S3 → ③ catalog → ④ query (Athena) → ⑤ transform (dbt) → ⑥ serve → ⑦–⑧ dashboard → user.
Dashed edges are control/observability (scheduler, secrets, DLQ, alarms).

![AWS cloud architecture](/images/architecture.png)

**Figure 2 — Data lifecycle (dbt medallion).** How the data is shaped from raw to product: raw S3 zones →
Glue catalog → staging → intermediate (EPA-2024 AQI) → marts (Parquet) → API + SARIMA forecast → dashboard.

![Data lifecycle (dbt medallion)](/images/architecture_lifecycle.png)

**AWS services used**

| Layer | AWS Service | Role |
|---|---|---|
| Orchestration | **EventBridge Scheduler** | 6 schedules drive every job (scale-to-zero, no servers) |
| Ingestion | **Lambda** (×3, arm64) | `batch_sync`, `streaming_producer`, `weather_ingest` |
| Streaming | **Kinesis Data Streams + Firehose** | near-real-time API → S3 (`raw/stream/`) |
| Storage | **S3** | raw lake, processed marts, static website; lifecycle + Intelligent-Tiering |
| Catalog | **Glue Data Catalog** | partition projection (no crawler) |
| Query/Transform | **Athena + dbt** (CodeBuild) | 17 dbt models, EPA-2024 AQI, 84 tests |
| Serving | **API Gateway + Lambda** | GeoJSON map + `/analytics/*` JSON |
| ML | **Lambda (ECR container)** | SARIMA 7-day PM2.5 forecast |
| Secrets | **Secrets Manager** | OpenAQ API key (no plaintext) |
| Reliability | **SQS** DLQs | streaming + batch dead-letter |
| Observability | **CloudWatch + SNS** | 15 alarms + a billing alarm; **AWS Budget** ($8) |
| State | **S3 remote backend** | versioned + SSE, native lockfile (no DynamoDB) |

**Data sources**

- **OpenAQ** — historical S3 archive (CSV.GZ, `us-east-1`) + REST API v3, **21 VN stations** (17
  Hanoi-area, 4 HCMC; 5 currently active). Sentinel `-999` filtered; PM2.5 capped at 500 µg/m³ in staging.
- **Open-Meteo ERA5** reanalysis — daily weather covariates (temperature, RH, wind, precipitation, PBL
  height). Both APIs are free.

## 4. Technical Deployment

### 4.1 Implementation Phases

| Phase | Focus | Outcome |
|---|---|---|
| 0–1 | Foundation & first slice | Terraform IaC, three ingestion paths, partition projection, first dbt marts, live map + API |
| 2–3 | Data quality & diagnostics | outlier/sensor-bias flags, IoT-Lens reliability gaps, diagnostic marts |
| 3–5 | Weather & forecasting | ERA5 covariates, feature engineering, SARIMA 7-day forecast (container Lambda) |
| 6–7 | BI, validation & Well-Architected | QuickSight/static dashboard, workshop validation, arm64/X-Ray, context-extension |
| 8–9 | Hardening & governance | secrets, DLQs, SSE, observability alarms, remote state, RIPER-5 governance harness |
| 10 | Reproducibility & reporting | fresh-clone reproducibility, business framing, this FCJ report |

### 4.2 Detailed Technical Requirements

- **Ingestion** — 3 arm64 Lambdas (python3.12): `batch_sync` (daily, OpenAQ archive → `raw/batch/`),
  `streaming_producer` (30 min, REST API v3 → Kinesis → Firehose → `raw/stream/`), `weather_ingest`
  (daily, ERA5 → `raw/weather/`). DLQs on the async paths; the OpenAQ key is read from Secrets Manager.
- **Transform** — dbt-athena-community on CodeBuild builds 2 staging + 2 intermediate + 13 marts (17
  total; default build excludes 4 `bi_disabled` diagnostic marts). AQI uses **EPA-2024** PM2.5/PM10
  breakpoints with piecewise-linear interpolation; composite AQI = worst pollutant.
- **Serving** — `aqi_api` Lambda behind API Gateway (`GET /` GeoJSON, `/analytics/{health,seasonal,
  compliance,forecast}` JSON); a Leaflet + Chart.js **static dashboard** on the S3 website.
- **ML** — `forecast_generate` (ECR container Lambda) fits SARIMA(1,1,1)(1,0,1,7) per active station,
  writes `mart_daily_forecast` (35 rows / 5 stations / 7-day) and emits holdout-RMSE to CloudWatch.
- **Security** — Secrets Manager (no plaintext key), least-privilege IAM, API Gateway throttling +
  reserved concurrency, S3 public access scoped to `dashboard/*`.

## 5. Timeline & Milestones (Sprints)

| Sprint | Window | Milestone |
|---|---|---|
| 1 | Wk 1 (25–29 Mar) | Foundation + first end-to-end slice (ingest → catalog → marts → API → map) |
| 2 | Wk 2 (30 Mar–8 Apr) | Data quality, ERA5 weather, SARIMA forecast, FCJ doc structure |
| 3 | Wk 3 (9–18 Apr) | BI layer, workshop validation, Well-Architected pass |
| 4 | Wk 7 (29–31 May) | Security/observability hardening, governance harness, remote state |
| 5 | Wk 8 (1–2 Jun) | Reproducibility, business framing, FCJ report, live end-to-end verification |

*(Full per-week detail in the [Worklog]({{% relref "/1-worklog" %}}). Weeks 4–6 covered parallel OTT
data projects; see the worklog landing.)*

## 6. Budget Estimation

**AWS services (estimated, steady-state)**

| AWS Service | Component / Usage | Cost (USD/month) |
|---|---|---|
| Amazon S3 | data lake + static site (~few GB, Intelligent-Tiering, lifecycle) | 0.25 |
| Amazon Athena | dbt builds + API queries (10 GB per-query scan cap) | 0.70 |
| AWS Lambda | 6 functions, arm64, scale-to-zero | 0.10 |
| Kinesis Data Streams + Firehose | on-demand, low volume | 0.55 |
| AWS CodeBuild | daily dbt run (~3–5 min) | 0.35 |
| Amazon CloudWatch + SNS | 15 alarms, logs, dashboard | 0.45 |
| Amazon API Gateway | HTTP API, low traffic | 0.05 |
| AWS Secrets Manager | 1 secret | 0.40 |
| Data transfer / misc | egress, SQS | 0.37 |
| **Total** | | **≈ 3.22** |

**Other costs**

| Category | Details | Cost (USD/month) |
|---|---|---|
| Third-party services | OpenAQ + Open-Meteo APIs (free tier) | 0.00 |
| **Project total** | | **≈ 3.22** (hard ceiling: AWS Budget $8) |

> **Cost scope & early validation.** These figures are the **pipeline's own incremental** cost. The
> project runs in a **shared AWS account** that also hosts unrelated workloads, so the *account-level*
> bill is not a direct measure of this pipeline. In the first days of operation (June 2026), the services
> **exclusive to this pipeline** were negligible — CodeBuild ≈ $0.06 and Athena ≈ $0.02 for a full dbt
> build, with Lambda / Glue / API Gateway ≈ $0 — consistent with the estimate above; the `openaq-pipeline`
> bucket holds ~207 MB and the on-demand Kinesis stream is low-volume. (Account-wide S3/Kinesis/OpenSearch
> charges in the same account belong to other projects, not this one.)

## 7. Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| **Cost overrun** | Low | Medium | 10 GB Athena per-query scan cap, scale-to-zero serverless, S3 tiering/lifecycle, and an **AWS Budget ($8)** with a `>$8/month` billing alarm. |
| **Data staleness / source gaps** | Medium | Medium | `completeness_check` (hourly `MissingStations`), a `DaysSinceLastNewMart` silent-death signal, a `mart-stale` alarm, and a query-based dbt freshness gate. |
| **OpenAQ API rate-limit / key exposure** | Low | High | key held in **Secrets Manager** (never in state/env), backoff on the producer, and a **DLQ** on the async path. |
| **Forecast inaccuracy** | Medium | Low | per-station SARIMA with **holdout-RMSE** emitted to CloudWatch + a `ForecastRMSE` alarm; forecast presented as indicative, not an SLA. |
| **Single-region availability** | Low | Low | accepted for a demo; the stack is fully reproducible via Terraform and can be redeployed in another region. |

## 8. Expected Results & Team

### 8.1 Expected Results

1. End-to-end pipeline live: ingest → catalog → marts → API → dashboard, on current data.
2. Correct EPA-2024 AQI, machine-verified by dbt **unit tests**.
3. 7-day SARIMA forecast live with RMSE monitoring.
4. Fully reproducible from `terraform apply` (verified from a fresh clone).
5. Well-Architected: no open high risks; within the cost envelope.

*All five are met and verified live — see the [Workshop]({{% relref "/5-workshop" %}}) for the
reproducible build, and §2.8 of the repository docs for the engineering record.*

### 8.2 Project Limitations

- **Demonstration scope**, not a funded public service: no real-user SLA, no regulatory consumer; bounded
  to the 21-station OpenAQ roster (5 currently active).
- **Gases (NO₂/O₃/SO₂/CO)** are retained raw but excluded from the AQI (they need ppm/ppb + sub-daily
  windows — a documented non-goal at daily grain).
- **QuickSight** is disabled (Enterprise-only); BI is delivered by the in-envelope static dashboard.

### 8.3 Implementation Team

| Name | Role | Contact |
|---|---|---|
| thanhtrung102 | FCJ Cloud Intern — sole designer & builder (data engineering, IaC, ML, BI) | thanhtrungnsl2003@gmail.com |
| FCJ Program Mentors | Guidance & review (AWS Study Group · First Cloud Journey) | [cloudjourney.awsstudygroup.com](https://cloudjourney.awsstudygroup.com/) |

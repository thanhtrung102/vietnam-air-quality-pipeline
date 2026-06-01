+++
title = "Workshop"
weight = 5
chapter = false
pre = " <b> 5. </b> "
+++

# Workshop — Build the Pipeline from Scratch

This workshop builds the entire Vietnam Air Quality pipeline on AWS from a clean clone, using
**Terraform** for every resource. It is reproducible end-to-end and was verified live on 2026-06-01.

## What you will build

- A **live Leaflet station map** (US EPA AQI per station) + a **4-sheet analytics dashboard**
  (Health Scorecard, Seasonal & Weather Drivers, Compliance & Trajectory, Forecast Monitor).
- A **SARIMA 7-day PM2.5 forecast** (container Lambda) with CloudWatch RMSE monitoring.
- **Fully reproducible infrastructure** — one `terraform apply` provisions ~82 resources.

> QuickSight is **optional** (it requires Enterprise edition). This deployment runs on QuickSight
> Standard, so the BI layer is delivered by an in-envelope **static dashboard** (Leaflet + Chart.js)
> that reads the same dbt marts via the `aqi_api` Lambda. The `quicksight_*.tf` files are parked in
> `terraform/_qs_disabled/`.

## Prerequisites at a glance

- AWS account + `terraform-admin`-style IAM user (region `ap-southeast-1`).
- Terraform ≥ 1.10, AWS CLI, Python 3.12, an OpenAQ API key.
- See **5.2 Prerequisites**.

## Reproducible build order

| Step | Section | Outcome |
|---|---|---|
| 1 | 5.2 Prerequisites | tooling, credentials, `terraform.tfvars` |
| 2 | 5.3 Storage & Catalog | S3, Glue (partition projection), Athena |
| 3 | 5.4 Ingestion | 3 Lambdas, Kinesis/Firehose, EventBridge schedules |
| 4 | 5.5 Transform & Serving | dbt-on-Athena, API + dashboard, SARIMA forecast, security |
| 5 | 5.6 Cleanup | tear everything down |

The full bilingual runbook lives in the repo under `docs/workshop/5.1`–`5.6`.

+++
title = "AWS FCJ Internship Report"
description = "AWS First Cloud Journey internship report — a fully serverless Vietnamese air-quality data pipeline (OpenAQ + ERA5 → S3 → Glue → Athena/dbt → API + ML forecast)."
+++

# Vietnam Air Quality Pipeline — AWS First Cloud Journey Internship Report

A fully **serverless data-engineering pipeline** on AWS that ingests, transforms, serves, and forecasts
air-quality data for **21 Vietnamese monitoring stations** (Hanoi + Ho Chi Minh City), built and operated
within a strict **~$3–8/month** single-operator cost envelope.

> **Live artefacts**
> - Station map + analytics dashboard (S3 static site): `http://openaq-pipeline-thanhtrung102.s3-website-ap-southeast-1.amazonaws.com/dashboard/index.html`
> - Source repository: `https://github.com/thanhtrung102/vietnam-air-quality-pipeline`

## Report contents

This report follows the AWS FCJ internship-report structure. All sections are written except **Section 4
(Events Participated)**, which remains a placeholder; the Proposal and Workshop are verified end-to-end.

| # | Section | Status |
|---|---|---|
| 1 | **Worklog** | ✅ 8 weeks |
| 2 | **Proposal** | ✅ complete |
| 3 | **Translated Blogs** | ✅ 3 blogs |
| 4 | Events Participated | _placeholder_ |
| 5 | **Workshop** | ✅ complete + reproducible |
| 6 | **Self-Assessment** | ✅ complete |
| 7 | **Sharing & Feedback** | ✅ complete |

## At a glance (verified live, 2026-06-01)

- **6 Lambdas** (python3.12 / arm64), Kinesis + Firehose streaming, Glue partition projection, Athena +
  **dbt** (17 models, **84 tests**), **SARIMA** 7-day forecast, API Gateway + Leaflet/Chart.js dashboard.
- **Reproducible**: every resource is Terraform; a fresh clone deploys in ~82 resources.
- **Well-Architected**: 6 pillars reviewed; 16 CloudWatch alarms (15 + billing) + an AWS Budget; no open high risks.

## Contributors

{{< ghcontributors "https://api.github.com/repos/thanhtrung102/vietnam-air-quality-pipeline/contributors" >}}

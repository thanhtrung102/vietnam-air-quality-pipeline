+++
title = "Week 1 Worklog"
weight = 1
chapter = false
pre = " <b> 1.1. </b> "
+++

### Week 1 Objectives (25–29 Mar 2026)

- Establish the repository, problem statement, architecture, and the Vietnamese station roster.
- Provision the core AWS infrastructure as **Terraform** (S3, Glue, Athena, Kinesis, IAM, CloudWatch).
- Stand up **ingestion**: a historical batch load from the OpenAQ S3 archive and a near-real-time
  streaming producer.
- Catalog the raw data with **Glue partition projection** (no crawler) and build the first **dbt** marts.
- Ship a first **end-to-end slice**: a live Leaflet station map served by an API over the AQI marts.

### Tasks carried out this week

| Day | Task | Start | Completion | Reference |
| :-- | :--- | :--- | :--- | :--- |
| 1 | **Project foundation & IaC** — repository structure, problem statement, architecture doc + ADRs, Vietnamese station IDs/archive exploration; first Terraform stack for S3, Glue, Athena, Kinesis, IAM, CloudWatch; historical S3 sync + daily incremental sync scripts; Kinesis producer for OpenAQ API v3. | 25/03/2026 | 25/03/2026 | [Repository](https://github.com/thanhtrung102/vietnam-air-quality-pipeline) |
| 2 | **Orchestration & first marts** — replaced a Kestra/Docker plan with **EventBridge Scheduler + Lambda** (Docker unavailable); `batch_sync` rewritten to use **boto3**; Athena external table with **partition projection** + OpenCSVSerde; dbt staging → intermediate → mart models with station metadata seed; AQI metrics + exceedance flags; Leaflet map, SNS event-driven sync, and the `aqi_api` endpoint. | 26/03/2026 | 26/03/2026 | [docs/PIPELINE-REPORT.md](https://github.com/thanhtrung102/vietnam-air-quality-pipeline/blob/main/docs/PIPELINE-REPORT.md) |
| 3 | **Dashboard storytelling & optimisation** — cigarette-equivalent, WHO-compliance and health-summary views; a correctness/cost/test-coverage optimisation pass; warehouse and dbt-format tuning. | 27/03/2026 | 27/03/2026 | [Proposal](../../2-proposal/) |
| 4 | **Defect cleanup & docs** — fixed critical code defects and dead code; resolved dbt build blockers; validated mart S3 placement; completed the README; added early QuickSight dashboard enhancements and the first architecture diagram. | 28/03/2026 | 28/03/2026 | — |
| 5 | **Data-accuracy hardening** — rendered the dashboard surfaces as static images and corrected data-accuracy errors found by cross-checking against real OpenAQ statistics (including filtering a sentinel value from an HCMC station). | 29/03/2026 | 29/03/2026 | [docs/DATA-QUALITY.md](https://github.com/thanhtrung102/vietnam-air-quality-pipeline/blob/main/docs/DATA-QUALITY.md) |

### Week 1 Achievements

- **A working end-to-end pipeline** in one week: OpenAQ archive + API → S3 → Glue (partition projection)
  → Athena/dbt marts → `aqi_api` → live Leaflet map.
- **Serverless-first orchestration** using EventBridge Scheduler + Lambda after Docker/Kestra proved
  unavailable — an early architecture decision that shaped the whole project.
- **US EPA AQI logic** and exceedance flags computed in dbt, with WHO-compliance and health framing on
  the dashboard.
- **Cost-aware foundations**: partition projection (no crawler) and an Athena scan-capped workgroup.

---

👉 **Outcome:** By the end of Week 1 the pipeline produced real, health-oriented air-quality output from
21 Vietnamese stations, end-to-end, on a fully serverless stack.

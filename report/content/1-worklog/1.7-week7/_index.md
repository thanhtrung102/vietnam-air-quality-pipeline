+++
title = "Week 7 Worklog"
weight = 7
chapter = false
pre = " <b> 1.7. </b> "
+++

**Projects:** OTT Data Analyst Agent
([aws-fcj-ott-data-analyst-agent](https://github.com/thanhtrung102/aws-fcj-ott-data-analyst-agent)) →
Vietnam AQ hardening
([vietnam-air-quality-pipeline](https://github.com/thanhtrung102/vietnam-air-quality-pipeline))

### Week 7 Objectives (28–31 May 2026)

- Build a Bedrock-backed **OTT Data Analyst Agent** as an FCJ workshop (Hugo + AWS CDK).
- Return to the air-quality pipeline for **security/observability hardening**.
- Install a **governance harness** and adopt a durable **remote Terraform state** backend.

### Tasks carried out this week

| Day | Task | Start | Completion | Reference |
| :-- | :--- | :--- | :--- | :--- |
| 1 | **OTT Data Analyst Agent** — scaffolded the FCJ workshop "OTT Data Analyst Agent" (Hugo + **AWS CDK**); verified end-to-end — 3 stacks deployed, 5 analyst queries green, and the single-page app live; fixed the invoke script to target the correct stack/region. | 28/05/2026 | 28/05/2026 | [Repository](https://github.com/thanhtrung102/aws-fcj-ott-data-analyst-agent) |
| 2 | **AQ security & resilience hardening** — secret-only OpenAQ key, SQS **DLQs**, SSE, single-source station roster; QuickSight disabled in favour of the static dashboard; Lambda row-parsing hardened with raise-not-exit and **walk-forward forecast RMSE**; unit tests for the ingestion Lambdas; dbt AQI macros extracted and diagnostic marts tagged `bi_disabled`; silent-failure metrics + CloudWatch alarms; completed the CodeBuild dbt image; live-verified reports + a verify-as-source-of-truth sweep. | 29/05/2026 | 30/05/2026 | [docs/PIPELINE-REPORT.md](https://github.com/thanhtrung102/vietnam-air-quality-pipeline/blob/main/docs/PIPELINE-REPORT.md) |
| 3 | **AQ governance & durability** — query-based dbt source-freshness gate + a weather test; installed the **RIPER-5 agent harness** with a live-state HARD GATE (audit suite green); stripped a fabricated `corrected_pm25` citation and relabelled it as an unvalidated heuristic; adopted a **remote S3 Terraform state** backend with the native S3 lockfile (no DynamoDB). | 31/05/2026 | 31/05/2026 | [docs/WELL-ARCHITECTED.md](https://github.com/thanhtrung102/vietnam-air-quality-pipeline/blob/main/docs/WELL-ARCHITECTED.md) |

### Week 7 Achievements

- **A deployed Bedrock data-analyst agent** (CDK, 3 stacks) answering analytics questions over an OTT
  dataset, with a live SPA front end.
- **Production-hardened AQ pipeline**: secrets-only credentials, DLQs, SSE, reserved concurrency, and
  silent-failure alarms.
- **Self-sufficient BI**: QuickSight (Enterprise-only) replaced by the static Leaflet + Chart.js
  dashboard, keeping the cost envelope.
- **Durable state + governance**: a remote S3 backend with native locking, and a RIPER-5 harness that
  enforces live-state verification before changes ship.

---

👉 **Outcome:** A third OTT deliverable (the agent) shipped, and the air-quality pipeline was brought up
to portfolio quality — secured, observable, tested, governed, and reproducible from a clean state.

+++
title = "Week 4 Worklog"
weight = 4
chapter = false
pre = " <b> 1.4. </b> "
+++

### Week 4 Objectives (29–31 May 2026)

- **Harden** the deployment for portfolio quality: security, observability, and testing.
- Replace the QuickSight dependency with an **in-envelope static dashboard**.
- Reconcile all documentation to **live-verified** ground truth.
- Install a **governance harness** (RIPER-5) and adopt a durable **remote Terraform state** backend.

> _The intensive build phase paused after 18 April; work resumed on 29 May for a dedicated hardening,
> verification, and reporting phase. The dates below reflect that real timeline._

### Tasks carried out this week

| Day | Task | Start | Completion | Reference |
| :-- | :--- | :--- | :--- | :--- |
| 1 | **Security & resilience hardening** — secret-only OpenAQ key, SQS **DLQs**, SSE, single-source station roster; QuickSight disabled and parked in favour of the static dashboard; Lambda row-parsing hardened with raise-not-exit and **walk-forward forecast RMSE**; unit tests for `batch_sync`/`kinesis_producer`/`weather_ingest`; dbt AQI macros extracted and 4 diagnostic marts tagged `bi_disabled`. | 29/05/2026 | 30/05/2026 | [docs/DATA-LIFECYCLE.md](https://github.com/thanhtrung102/vietnam-air-quality-pipeline/blob/main/docs/DATA-LIFECYCLE.md) |
| 2 | **Observability & live-verified docs** — silent-failure metrics + CloudWatch alarms and Lambda `source_code_hash`; completed the CodeBuild dbt image so the marts build; authored live-verified reports (PIPELINE-REPORT, DATA-LIFECYCLE, an 8-lens architecture evaluation) and a root README doc-map; reconciled context against live AWS. | 30/05/2026 | 30/05/2026 | [docs/PIPELINE-REPORT.md](https://github.com/thanhtrung102/vietnam-air-quality-pipeline/blob/main/docs/PIPELINE-REPORT.md) |
| 3 | **Data-quality gates & governance** — query-based dbt source-freshness gate (storable, scan-cheap) recalibrated to 21 days + a weather test; installed the **RIPER-5 agent harness** with a live-state HARD GATE and made the audit suite green; live-verified deployed specs before push. | 31/05/2026 | 31/05/2026 | [docs/DATA-QUALITY.md](https://github.com/thanhtrung102/vietnam-air-quality-pipeline/blob/main/docs/DATA-QUALITY.md) |
| 4 | **Integrity & durability fixes** — stripped a fabricated `corrected_pm25` citation and relabelled it as an unvalidated heuristic; tagged 3 QuickSight-only leaf marts `bi_disabled`; adopted a **remote S3 Terraform state** backend with the native S3 lockfile (no DynamoDB). | 31/05/2026 | 31/05/2026 | [docs/WELL-ARCHITECTED.md](https://github.com/thanhtrung102/vietnam-air-quality-pipeline/blob/main/docs/WELL-ARCHITECTED.md) |

### Week 4 Achievements

- **Production-hardened**: secrets-only credentials, DLQs, SSE, reserved concurrency, and silent-failure
  alarms — no open high risks in the Well-Architected review.
- **Self-sufficient BI**: QuickSight (Enterprise-only) replaced by a static Leaflet + Chart.js dashboard
  reading the same marts, keeping the cost envelope.
- **Documentation = ground truth**: every report reconciled against live AWS via a verify-as-source pass.
- **Durable state + governance**: remote S3 backend with native locking, and a RIPER-5 harness enforcing
  live-state verification before changes ship.

---

👉 **Outcome:** By the end of Week 4 the pipeline was secured, observable, tested, and reproducible from
a clean state, with documentation that matches the running system exactly.

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

| Day | Task | Start | Completion | Commits |
| :-- | :--- | :--- | :--- | :--- |
| 1 | **OTT Data Analyst Agent** — scaffolded the FCJ workshop "OTT Data Analyst Agent" (Hugo + **AWS CDK**); verified end-to-end — 3 stacks deployed, 5 analyst queries green, and the single-page app live; fixed the invoke script to target the correct stack/region. | 28/05/2026 | 28/05/2026 | [`e7d35a5`], [`d4a5992`], [`6bce4af`] |
| 2 | **AQ security & resilience hardening** — secret-only OpenAQ key, SQS **DLQs**, SSE, single-source station roster; QuickSight disabled in favour of the static dashboard; Lambda row-parsing hardened with raise-not-exit and **walk-forward forecast RMSE**; unit tests for the ingestion Lambdas; dbt AQI macros extracted and diagnostic marts tagged `bi_disabled`; silent-failure metrics + CloudWatch alarms; completed the CodeBuild dbt image; live-verified reports + a verify-as-source-of-truth sweep. | 29/05/2026 | 30/05/2026 | [`12d3d0d`], [`9673e20`], [`5f23455`], [`2f98e25`] |
| 3 | **AQ governance & durability** — query-based dbt source-freshness gate + a weather test; installed the **RIPER-5 agent harness** with a live-state HARD GATE (audit suite green); stripped a fabricated `corrected_pm25` citation and relabelled it as an unvalidated heuristic; adopted a **remote S3 Terraform state** backend with the native S3 lockfile (no DynamoDB). | 31/05/2026 | 31/05/2026 | [`424e33b`], [`092c037`], [`19511db`], [`d720baf`] |

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

[`e7d35a5`]: https://github.com/thanhtrung102/aws-fcj-ott-data-analyst-agent/commit/e7d35a5
[`d4a5992`]: https://github.com/thanhtrung102/aws-fcj-ott-data-analyst-agent/commit/d4a5992
[`6bce4af`]: https://github.com/thanhtrung102/aws-fcj-ott-data-analyst-agent/commit/6bce4af
[`12d3d0d`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/12d3d0d
[`9673e20`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/9673e20
[`5f23455`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/5f23455
[`2f98e25`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/2f98e25
[`424e33b`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/424e33b
[`092c037`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/092c037
[`19511db`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/19511db
[`d720baf`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/d720baf

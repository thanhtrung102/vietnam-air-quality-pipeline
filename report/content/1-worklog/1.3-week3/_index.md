+++
title = "Week 3 Worklog"
weight = 3
chapter = false
pre = " <b> 1.3. </b> "
+++

### Week 3 Objectives (9–18 Apr 2026)

- Deploy a **business-intelligence** layer (Amazon QuickSight) over the marts.
- Wire the **daily dbt build** to run automatically.
- **Validate the workshop** (5.1–5.6) page-by-page against the real codebase and the FCJ template.
- Apply **Well-Architected** improvements and fix reproduction blockers.

### Tasks carried out this week

| Day | Task | Start | Completion | Reference |
| :-- | :--- | :--- | :--- | :--- |
| 1 | **QuickSight BI** — deployed QuickSight Phase 1+2 (IAM, Athena data source, 9 SPICE datasets), then Phase 3+4 (analysis, dashboard, DIRECT_QUERY); wired the **daily dbt build** and fixed the EventBridge → CodeBuild target. | 10/04/2026 | 14/04/2026 | [Workshop 5.5](../../5-workshop/5.5-transform-serving/) |
| 2 | **Dashboard expansion & code health** — expanded dashboards using previously unused raw fields; code-health pass (dead imports, boolean naming, mart de-duplication); fixed broken tests; FCJ doc sections and navigation. | 15/04/2026 | 15/04/2026 | — |
| 3 | **Workshop fact-checking** — fact-checked and validated **workshop pages 5.1–5.6** against the codebase and the FCJ sample template (sensor counts, schedules, resource counts, names, outputs, response formats); added the `architecture.yaml` diagram (awslabs diagram-as-code) and fixed an XSS issue in the dashboard. | 16/04/2026 | 16/04/2026 | [Workshop](../../5-workshop/) |
| 4 | **Well-Architected & reproducibility** — applied Well-Architected improvements (arm64, X-Ray, right-sizing, reliability); added the QuickSight workshop section and S3 static-website infrastructure; fixed two reproduction blockers found during inspection. | 17/04/2026 | 17/04/2026 | [docs/WELL-ARCHITECTED.md](https://github.com/thanhtrung102/vietnam-air-quality-pipeline/blob/main/docs/WELL-ARCHITECTED.md) |
| 5 | **Correctness & live verification** — fixed a `mart_daily_air_quality` GROUP BY bug and updated the workshop docs with **live-verified** values. | 18/04/2026 | 18/04/2026 | [Workshop 5.3](../../5-workshop/5.3-storage-catalog/) |

### Week 3 Achievements

- **BI layer delivered**: QuickSight analysis + dashboard over the marts, with the daily dbt build
  automated via CodeBuild.
- **A validated, reproducible workshop**: every 5.x page fact-checked against the live codebase and the
  FCJ template.
- **Well-Architected pass**: arm64 Lambdas, tracing, right-sizing, and reliability fixes.
- **An AWS-icon architecture diagram** generated from a definition file (diagram-as-code).

---

👉 **Outcome:** By the end of Week 3 the project had a BI layer, an automated daily build, and a
workshop runbook whose every claim had been checked against the running system.

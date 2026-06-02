+++
title = "Week 2 Worklog"
weight = 2
chapter = false
pre = " <b> 1.2. </b> "
+++

### Week 2 Objectives (30 Mar–8 Apr 2026)

- Deepen **data quality**: outlier and sensor-bias flags, reliability gaps from the IoT Well-Architected
  Lens.
- Add **diagnostic analytics** marts and charts beyond the basic daily AQI view.
- Ingest **weather covariates** (Open-Meteo ERA5) and engineer predictive features.
- Build a **7-day PM2.5 forecast** and deploy it as a container Lambda.
- Restructure the documentation into the **FCJ workshop** format with an architecture diagram.

### Tasks carried out this week

| Day | Task | Start | Completion | Reference |
| :-- | :--- | :--- | :--- | :--- |
| 1 | **Data-quality & Phase 0–2** — outlier/sensor-bias flags; completed in-progress Phase 0 work (7 mart/dashboard additions); Phase 1 closed 7 IoT Well-Architected reliability gaps; Phase 2 added 2 diagnostic marts + 2 charts. | 30/03/2026 | 06/04/2026 | [docs/DATA-QUALITY.md](https://github.com/thanhtrung102/vietnam-air-quality-pipeline/blob/main/docs/DATA-QUALITY.md) |
| 2 | **Weather, features & forecasting (Phase 3–6)** — Open-Meteo **ERA5** ingestion + 4 weather dbt models; predictive feature engineering (lag mart, feature stats, holiday seed); SARIMA + Prophet forecast Lambda + a forecast dashboard sheet; CRISP-DM case-study docs. | 07/04/2026 | 07/04/2026 | [Workshop 5.5](../../5-workshop/5.5-transform-serving/) |
| 3 | **Forecast deployment & guards** — deployed a **SARIMA-only ECR container Lambda** for 7-day PM2.5 forecasting; added a staleness guard and a smarter completeness check; fixed five Athena/dbt correctness bugs found during a reproduction run. | 07/04/2026 | 07/04/2026 | [docs/PIPELINE-REPORT.md](https://github.com/thanhtrung102/vietnam-air-quality-pipeline/blob/main/docs/PIPELINE-REPORT.md) |
| 4 | **FCJ documentation structure** — replaced the ad-hoc docs with the **FCJ workshop structure**; produced a draw.io architecture diagram and corrected four codebase mismatches in it. | 08/04/2026 | 08/04/2026 | [Workshop](../../5-workshop/) |

### Week 2 Achievements

- **Weather-aware analytics**: ERA5 covariates joined into the marts, enabling seasonal/weather-driver
  analysis.
- **Predictive layer live**: a SARIMA 7-day PM2.5 forecast running as a container Lambda, with staleness
  and completeness safeguards.
- **Diagnostic depth**: additional marts and charts moved the dashboard from descriptive to diagnostic.
- **FCJ-aligned docs**: the repository's documentation was restructured to the workshop format used in
  this report.

---

👉 **Outcome:** By the end of Week 2 the pipeline was not just descriptive but **predictive and
weather-aware**, and the documentation had been reorganised into the FCJ workshop shape.

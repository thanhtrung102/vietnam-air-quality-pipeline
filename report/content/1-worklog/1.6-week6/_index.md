+++
title = "Week 6 Worklog"
weight = 6
chapter = false
pre = " <b> 1.6. </b> "
+++

**Project:** OTT SDLF data-lake pipeline ·
[ott-sdlf](https://github.com/thanhtrung102/ott-sdlf)

### Week 6 Objectives (20–26 May 2026)

- Production-harden the SDLF pipeline and remove dead code.
- Produce a **live-verified FCJ workshop** on the AWS-workshop visual theme.
- Consolidate the analytics surface to a single hosted **dashboard**.
- Audit the project end-to-end and propose a first-principles **MVP redesign**.

### Tasks carried out this week

| Day | Task | Start | Completion | Reference |
| :-- | :--- | :--- | :--- | :--- |
| 1 | **FCJ workshop + verification** — production hardening + dead-code cleanup; pivoted the site to the FCJ workshop template and adopted the **hugo-theme-learn** FCJ frontend (`danielleit241/aws-fcj-report`) — the same theme later used for this air-quality report; added a Live Verification chapter with `verify_live.py`; activated and verified Lake Formation column-level RBAC enforcement. | 20/05/2026 | 20/05/2026 | [Repository](https://github.com/thanhtrung102/ott-sdlf) |
| 2 | **Dashboard hosting & fixes** — hosted the search-analytics dashboard on **S3 + CloudFront**, sourced from the curated layer; closed the LUT-Refresh classifier handoff and added a Stage-A failure alarm; centralized the dashboard and fixed classification/null-keyword bucketing; removed the unused gold layer. | 21/05/2026 | 21/05/2026 | — |
| 3 | **Consolidation & reproducibility** — consolidated to a single dashboard surface (retired the analytics API and content-gap Lambda once unused); reconciled CloudFormation templates with the live stack state so templates own all drift; fixed workshop reproducibility bugs found in an end-to-end verbatim run; deployed the Hugo workshop site via GitHub Actions. | 22/05/2026 | 22/05/2026 | — |
| 4 | **Audit & MVP redesign** — full project review with dead-code removal and input-escaping hardening; Glue performance (cache the source DataFrame, cache+count before write); authored a first-principles, pedagogy-first **MVP redesign proposal** plus an ARCHITECTURE doc, a decision log, and READMEs for all 9 stacks. | 26/05/2026 | 26/05/2026 | — |

### Week 6 Achievements

- **An FCJ-format, live-verified workshop** for the SDLF pipeline on the AWS-workshop theme — and the
  first use of the FCJ `hugo-theme-learn` frontend that this air-quality report later adopted.
- **A single, hosted dashboard** on S3 + CloudFront, after consolidating away redundant API/Lambda
  surfaces.
- **Template/live reconciliation**: CloudFormation made the single source of truth for the deployed
  stack.
- **A reflective audit + MVP redesign**: a first-principles proposal for a leaner, more teachable
  version, with architecture and decision documentation.

---

👉 **Outcome:** The OTT SDLF project ended week 6 hardened, documented as a reproducible FCJ workshop,
and accompanied by a considered proposal for how to rebuild it more simply.

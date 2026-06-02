+++
title = "Self-Assessment"
weight = 6
chapter = false
pre = " <b> 6. </b> "
+++

Over the course of this **First Cloud Journey (FCJ)** internship, I learned a broad set of AWS services
and — more importantly — applied them by building four real, deployable data projects end-to-end: the
**Vietnam Air Quality pipeline** (the primary deliverable documented in this report), an **OTT Search
Analytics pipeline**, an **OTT data-lake pipeline on the Serverless Data Lake Framework (SDLF)**, and a
**Bedrock-backed OTT Data Analyst Agent**. The project work spanned late March to early June 2026.

Across these projects I grew most in **serverless data engineering** (S3, Glue, Athena, Kinesis, Lambda,
EventBridge), **infrastructure as code** (Terraform and CloudFormation/SDLF), **analytics engineering**
(dbt modelling, data-quality testing, time-series forecasting), and **governance and security**
(Lake Formation column-level access, Well-Architected reviews, secrets handling, observability). I also
learned to hold myself to a higher bar of correctness — verifying every documented claim against the
live AWS account rather than against my own assumptions. The sections below are an honest reflection on
where I did well and where I still need to improve.

### Self-Evaluation

| No. | Criteria | Description | Good | Fair | Average |
| :-- | :--- | :--- | :--: | :--: | :--: |
| 1 | Professional knowledge and skills | Designed and shipped four end-to-end AWS data pipelines (ingestion → catalog → transform → serving), with IaC, forecasting, and BI. | ✅ | | |
| 2 | Learning ability | Picked up SDLF, Lake Formation, QuickSight, dbt, and Bedrock agents from scratch and applied each in a working deliverable. | ✅ | | |
| 3 | Proactivity | Consistently went beyond the MVP — added forecasting, Well-Architected hardening, and a governance harness without being asked. | ✅ | | |
| 4 | Sense of responsibility | Live-verified every reported metric, hardened security, and corrected my own mistakes openly (e.g. removing a fabricated data citation). | ✅ | | |
| 5 | Discipline | Delivered consistently within each project, but the overall cadence had a multi-week gap between projects that steadier planning would avoid. | | ✅ | |
| 6 | Eagerness to improve | Ran iterative audits, end-to-end reproduction runs, and even authored a first-principles MVP-redesign proposal for one project. | ✅ | | |
| 7 | Communication | Documentation and written reporting were strong; proactive verbal check-ins with mentors are something I should do more often. | | ✅ | |
| 8 | Teamwork | Projects were largely individual, so I had limited opportunity to demonstrate collaboration in a team setting. | | ✅ | |
| 9 | Professional conduct | Maintained clean git history, honest reporting, and respect for cost and security constraints throughout. | ✅ | | |
| 10 | Problem-solving mindset | Debugged hard issues independently — CI/CD IAM chains, Athena partition projection, SARIMA forecasting, Glue timeouts. | ✅ | | |
| 11 | Contribution to project/organization | Delivered four reproducible FCJ workshops and a published portfolio that others can redeploy from a clean clone. | ✅ | | |
| 12 | Overall | A productive internship with strong technical output; the main growth areas are consistency and collaboration. | ✅ | | |

### Areas for Improvement

- **Consistency and time management** — keep a steadier working cadence and avoid long gaps between
  projects; plan milestones so progress is continuous rather than bursty.
- **Communication with mentors and peers** — check in more proactively and earlier, rather than relying
  on documentation to carry the message after the fact.
- **Teamwork and collaboration** — seek out group settings and peer review to balance an internship that
  was heavily individual project work.
- **Scoping discipline** — resist over-engineering; the OTT SDLF MVP-redesign taught me to build the
  smallest correct version first and add depth only when it earns its place.
- **Test-first habits** — bring testing and observability in earlier in each project instead of adding
  them during a late hardening phase.
- **Domain validation** — verify domain and scientific claims against authoritative sources before
  shipping (the corrected-PM2.5 citation I had to strip is a lesson I will not repeat).

---

👉 **Overall:** This internship took me from learning AWS services to delivering production-grade,
reproducible data systems on the cloud. I am proud of the technical depth and the honesty of the work,
and I have a clear, concrete picture of how to become a more consistent and collaborative engineer next.

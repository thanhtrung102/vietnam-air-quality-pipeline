+++
title = "Week 8 Worklog"
weight = 8
chapter = false
pre = " <b> 1.8. </b> "
+++

**Project:** Vietnam Air Quality pipeline ·
[vietnam-air-quality-pipeline](https://github.com/thanhtrung102/vietnam-air-quality-pipeline)

### Week 8 Objectives (1–2 Jun 2026)

- Frame the project's **business context** for the FCJ proposal.
- Make the **workshop reproducible end-to-end** on a fresh machine and verify it live.
- Finish the **forecast subsystem** and the **L4 data-quality** hardening.
- Build and deploy the **FCJ internship report site** and verify the whole system live.

### Tasks carried out this week

| Day | Task | Start | Completion | Commits |
| :-- | :--- | :--- | :--- | :--- |
| 1 | **Business framing & reproducibility** — authored `BUSINESS-CONTEXT.md` (FCJ proposal/business framing); made workshop **5.1–5.6 reproducible end-to-end** on a fresh machine; fixed the **SARIMA forecast subsystem**; completed **L4 data-quality** hardening; shipped the QuickSight-alternative analytics dashboard; reconciled `bi_disabled` drift and the billing threshold. | 01/06/2026 | 01/06/2026 | [`2df9fc2`], [`adbbb27`], [`08f40d8`], [`192b8af`], [`9db52f2`] |
| 2 | **FCJ report site & live verification** — built the **Hugo internship-report site** (hugo-theme-learn, AWS workshop palette) with the Proposal, Workshop, Translated Blogs, and this Worklog; audited the architecture diagram; verified the deployed pipeline **live end-to-end** — 5 active stations, a 35-row 7-day forecast, dbt 84/84 tests, and the $8 AWS Budget. | 01/06/2026 | 02/06/2026 | [`d1803ee`], [`0674ab5`], [`ea527d9`], [`03f31d8`] |

### Week 8 Achievements

- **Business-grounded proposal**: a clear problem statement, objectives, and success criteria tied to
  the engineering.
- **Reproducible from scratch**: the workshop deploys the whole stack with Terraform and was confirmed
  to build from a clean clone.
- **Forecast & data-quality finalised**: a corrected SARIMA subsystem and a hardened test suite
  (84 tests, all passing).
- **A live internship report**: this site, published to GitHub Pages, with every headline metric
  verified against the running AWS account.

---

👉 **Outcome:** The internship's primary deliverable was completed, reproducible, and documented as a
live FCJ report — with all success criteria met and verified against the deployed system.

[`2df9fc2`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/2df9fc2
[`adbbb27`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/adbbb27
[`08f40d8`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/08f40d8
[`192b8af`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/192b8af
[`9db52f2`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/9db52f2
[`d1803ee`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/d1803ee
[`0674ab5`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/0674ab5
[`ea527d9`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/ea527d9
[`03f31d8`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/03f31d8

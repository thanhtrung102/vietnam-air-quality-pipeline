+++
title = "Week 5 Worklog"
weight = 5
chapter = false
pre = " <b> 1.5. </b> "
+++

**Project:** OTT SDLF data-lake pipeline ·
[ott-sdlf](https://github.com/thanhtrung102/ott-sdlf)

### Week 5 Objectives (13–19 May 2026)

- Build an OTT analytics data lake on the AWS **Serverless Data Lake Framework (SDLF)**.
- Deliver **analytics Lambdas** (content-gap and trending-keywords) over the curated layer.
- Stand up **AWS-native CI/CD** (CodePipeline + CodeConnections) for the whole stack.
- Add **fine-grained security** (Lake Formation column-level permissions) and a serving **API**.

### Tasks carried out this week

| Day | Task | Start | Completion | Commits |
| :-- | :--- | :--- | :--- | :--- |
| 1 | **Analytics layer + CI/CD** — Content Gap and Trending Keywords analytics Lambdas (hour heatmap, guest/auth demand, network abandonment); an HTML dashboard in the Content Gap Lambda; an AWS-native **CodePipeline** CI/CD stack (via CodeConnections); a gold CTAS + gold data-quality stage; an Athena workgroup `sdlf-ott` and a Glue job bookmark. | 13/05/2026 | 13/05/2026 | [`637f64f`], [`f9e718c`], [`8443b26`], [`7dfea60`] |
| 2 | **Fine-grained security + API** — **Lake Formation column-level permissions** on `user_id_hashed`; an **HTTP API Gateway** (`GET /trending`, `GET /content-gaps`); unified the DQ stacks into a single parameterized template (SDLF pattern); registered all uncatalogued data in the Glue catalog. | 14/05/2026 | 14/05/2026 | [`4b3970f`], [`30ec606`], [`39a2414`], [`07faa0e`] |
| 3 | **Database design & correctness** — applied 9 database-design fixes across schema, catalog, and API; fixed critical Glue-job bugs and established a curated-catalog schema contract; addressed all 11 remaining evaluation findings; wrote comprehensive pipeline documentation (10 sections). | 15/05/2026 | 15/05/2026 | [`6a7593f`], [`d95b4d4`], [`888a196`], [`cc9a33a`] |

### Week 5 Achievements

- **A full SDLF data lake** for OTT analytics: raw → curated → gold, driven by the Serverless Data Lake
  Framework's stage pattern.
- **Two analytics Lambdas** (content gap, trending keywords) with their own data-quality stage and DLQs.
- **AWS-native CI/CD**: a CodePipeline stack wired through CodeConnections, with the IAM hardened
  iteratively until deploys were clean.
- **Column-level security**: Lake Formation permissions restricting `user_id_hashed`, plus an HTTP API
  for the analytics outputs.

---

👉 **Outcome:** By mid-week 5 the OTT SDLF pipeline was a deployable, secured, CI/CD-driven data lake
with analytics serving over an API.

[`637f64f`]: https://github.com/thanhtrung102/ott-sdlf/commit/637f64f
[`f9e718c`]: https://github.com/thanhtrung102/ott-sdlf/commit/f9e718c
[`8443b26`]: https://github.com/thanhtrung102/ott-sdlf/commit/8443b26
[`7dfea60`]: https://github.com/thanhtrung102/ott-sdlf/commit/7dfea60
[`4b3970f`]: https://github.com/thanhtrung102/ott-sdlf/commit/4b3970f
[`30ec606`]: https://github.com/thanhtrung102/ott-sdlf/commit/30ec606
[`39a2414`]: https://github.com/thanhtrung102/ott-sdlf/commit/39a2414
[`07faa0e`]: https://github.com/thanhtrung102/ott-sdlf/commit/07faa0e
[`6a7593f`]: https://github.com/thanhtrung102/ott-sdlf/commit/6a7593f
[`d95b4d4`]: https://github.com/thanhtrung102/ott-sdlf/commit/d95b4d4
[`888a196`]: https://github.com/thanhtrung102/ott-sdlf/commit/888a196
[`cc9a33a`]: https://github.com/thanhtrung102/ott-sdlf/commit/cc9a33a

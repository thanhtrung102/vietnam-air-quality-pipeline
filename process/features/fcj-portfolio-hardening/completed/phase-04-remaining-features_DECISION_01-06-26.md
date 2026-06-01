# Phase 04 — Remaining Features / Proposals: Decision Record

**Date:** 01-06-26 · **Status:** ✅ VERIFIED (decision phase — no build was the correct outcome for the in-envelope set)
**Parent:** `fcj-portfolio-hardening_PLAN_01-06-26.md`

"Proceed with all remaining features and proposals" was assessed against the constraint envelope and
the data's actual capability (live-state + domain HARD GATE). The honest result: **the remaining set
contains no feature that is both in-envelope AND correct to build right now.** Each is dispositioned
below with rationale, rather than shipping something wrong. This is the FCJ-defensible "considered and
decided" record.

| # | Feature / proposal | Source | Decision | Rationale |
|---|---|---|---|---|
| 1 | **Multi-pollutant AQI sub-indices** (NO₂/O₃/SO₂/CO) | `backlog/example-complex-prd.md`; `mart_daily_air_quality.sql` comment | **DOCUMENT AS NON-GOAL** (+ design sketch → backlog) | OpenAQ reports gases in µg/m³, but EPA AQI needs **ppm/ppb** + **sub-daily windows** (NO₂/SO₂ 1-hr, O₃/CO 8-hr). Our marts are **daily-grain**, and VN roster stations are PM-centric (sparse/absent gas coverage). A daily-grain "gas AQI" would be **methodologically wrong** — worse than none. Building it correctly needs a new sub-daily mart + µg/m³→ppb conversion (MW + standard T/P) + stations that actually report gases. Out of envelope and low-value for the demo. |
| 2 | **NowCast current-conditions index** | `RESEARCH-WORKFLOW.md` L2 | **DOCUMENT AS NON-GOAL** | NowCast is a sub-daily "current AQI" weighting; the pipeline is daily-grain by design. Not needed for the daily analytics narrative. |
| 3 | **Validated low-cost-sensor correction** (Barkjohn/κ-Köhler) | `mart_daily_air_quality.sql`; L2 | **DEFER (external trigger)** | Requires a physical **collocation campaign** against a reference monitor — cannot be produced from existing data. The false citation was already stripped; `corrected_pm25` is clearly labelled UNVALIDATED. Trigger: a collocation dataset becomes available. |
| 4 | **Option-D — un-flag HCMC outlier `6273386`** | dashboard HCMC thread | **DECLINE (keep flagged)** | The `is_outlier_station=1` flag was a deliberate data-quality decision (readings ≫ all other HCMC stations + IQAir reference). No evidence it is resolvable from data alone; un-flagging would reintroduce known-bad readings into every city aggregate. The dashboard notes (commit `fdda4b2`) already explain the HCMC map gap honestly — the correct UX fix, already shipped. |
| 5 | **Incremental marts** (`insert_overwrite`) | ADR / ARCH-EVAL | **DEFER (scale trigger)** | Full-refresh CTAS is ~cents/mo at 1.39 M rows. Trigger: history > 1–2 yr or scan cost becomes material. ADR-logged in `WELL-ARCHITECTED.md`. |
| 6 | **Enforced model contracts** | `RESEARCH-WORKFLOW.md` L4 | **DEFER** | Athena contract enforcement is brittle to type-name drift; high build-churn for a single-operator demo. Rationale in `DATA-QUALITY.md`. |
| 7 | **Elementary observability** | L4 | **DECLINE** | Materialises its own models + artifacts schema → recurring Athena cost, out of envelope. The `DaysSinceLastNewMart` alarm + singular freshness tests cover the anomaly case. |
| 8 | **Redshift Serverless warehouse** | reference workshop | **DECLINE** | Athena covers the query need at ~1/9th the cost; Redshift is the reference workshop's single biggest cost line. Out of envelope. |
| 9 | **Live QuickSight (Enterprise)** | workshop 5.x | **DECLINE** | Account is QuickSight Standard; replaced by the in-envelope static Analytics dashboard. |
| 10 | **WAF on public API** | ARCH-EVAL Security | **DECLINE (accepted residual)** | ~$5+/mo floor exceeds the whole envelope for a read-only public-data GET; throttle + reserved-concurrency cap the blast radius. `WELL-ARCHITECTED.md` R3. |
| 11 | **Dedicated CloudTrail trail** | WA Security | **DECLINE (accepted residual)** | 90-day default Event history at $0 suffices for a demo. `WELL-ARCHITECTED.md` R4. |

**Net:** 0 builds, 2 documented non-goals, 4 defers (with triggers), 5 declines (envelope/data justified).
The one feature with portfolio appeal (multi-pollutant AQI) is correctly **not** built — shipping a
daily-grain gas AQI would be a domain error. A proper design sketch is parked in `backlog/` for if/when
gas-reporting stations + sub-daily aggregation are justified.

**Verification:** decision-only phase; no runtime change, so no live gate beyond the evidence cited
above (each disposition traces to an existing doc/data fact).

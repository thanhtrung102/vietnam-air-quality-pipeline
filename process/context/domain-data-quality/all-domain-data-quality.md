# Domain Science & Data Quality — Context Group

Last updated: 2026-05-31 (domain claims web-verified against EPA / WHO / QCVN / primary literature).
**Correctness-critical.** Parent: `process/context/all-context.md`.

## Scope

The air-quality science the marts encode (EPA AQI, NowCast, WHO/QCVN exceedance, health equivalents),
the data-quality filters, low-cost-sensor correction, and station-roster semantics.

## Read when

Touching any AQI/health computation, a DQ filter, the sensor correction, or interpreting station data.
**Mandatory before any "this AQI/health number is correct/wrong" claim** — settle it against the
authoritative standard AND a live data probe (RESEARCH-WORKFLOW Lane 2 + HARD GATE).

## Verified domain standards (May 2026)

| Standard | Authoritative value | Status in code |
|---|---|---|
| EPA PM2.5 AQI breakpoints (post-2024, eff. 2024-05-06) | AQI 50↔9.0, 100↔35.4, 150↔55.4, **200↔125.4**, 300↔225.4, 500↔325.4 µg/m³; input **truncated to 0.1** | CONFIRMED correct in `mart_daily_air_quality.sql` + `mart_health_summary.sql` (re-verify bp200=125.4, not legacy 150.4) |
| NowCast (PM) | past 12 h, weight `w = c_min/c_max` floored at 0.5; differs from ozone (8 h) | required only for "current conditions"; daily AQI is not live |
| WHO 2021 AQG PM2.5 | 24-h **15**, annual **5** µg/m³ | CONFIRMED |
| Vietnam QCVN 05:2023/BTNMT PM2.5 | 24-h **50**, annual **25** µg/m³ | CONFIRMED |
| Cigarette-equivalent | 22 µg/m³ ≈ 1 cig/day (Berkeley Earth) — **long-term mortality-risk analogy**, not acute equivalence | CONFIRMED (relabel as risk analogy) |

## ✅ RESOLVED (Fix #3, 2026-05-31) — `corrected_pm25` false citation stripped + relabeled

> **Status:** Fix #3 (minimum) applied 2026-05-31 (plan
> `process/general-plans/completed/fix-corrected-pm25-false-citation_PLAN_2026-05-31.md`). The false
> "EPA/Jayaratne" citation was removed from `mart_daily_air_quality.sql` (header, RH-CTE comment, inline
> block) and all three `schema.yml` `corrected_pm25` descriptions; the stale `/1.50` header comment was
> reconciled to the deployed `/(1+0.24·RH)` formula; the column is now labeled an **unvalidated humidity
> heuristic** with a **do-not-use-for-AQI/health** caveat. The compute logic was **unchanged**
> (value-neutral; verified: live `corrected_pm25` byte-identical, `dbt parse` + 85 lambda tests green).
> `corrected_pm25` has no live AQI/health consumer (passthrough feature in `mart_aq_weather_daily` /
> `mart_lagged_features` only). **Fixes #1/#2 below remain open future work** (need a Vietnam collocation
> campaign). The original defect analysis is preserved below for the record.

---

### Original defect analysis (point-in-time; P0, now resolved by Fix #3)

The deployed low-cost-sensor correction is `corrected_pm25 = avg_value / (1 + 0.24 × RH_fraction)`,
attributed in `models/marts/schema.yml` to **"EPA/Jayaratne"**. Web verification (2026-05-31):

- **The citation is false.** No Jayaratne et al. correction of this algebraic form exists. Jayaratne
  2018 (AMT 11:4883) *documents* RH-driven over-reading but publishes no `1/(1+0.24·RH)` formula. EPA
  does not publish this form either.
- **The functional form is wrong physics.** Real hygroscopic-growth correction is **nonlinear**
  (κ-Köhler): `PM_dry = PM_wet / (1 + κ/(100/RH − 1))`, which diverges as RH→100%. A linear
  `(1 + 0.24·RH_fraction)` divisor cannot capture this; the `0.24` constant traces to no source.
- **Direction is defensible, magnitude is not validated.** It monotonically deflates inflated wet
  readings, but is an unvalidated heuristic, not a cited method.

**Required action (three options ranked):**
1. *Preferred (FUTURE):* replace with the validated **Barkjohn US PurpleAir** eq (`0.524·PA_cf1 − 0.0862·RH +
   5.75`) **only after local Vietnam collocation** (Barkjohn is US-aerosol/PurpleAir-specific — do not
   ship US coefficients blind). Needs a reference+low-cost collocation campaign + `PA_cf1` raw channel — deferred.
2. *(FUTURE):* Use a κ-Köhler form with a locally-fitted κ. Also needs collocation — deferred.
3. *Minimum (✅ APPLIED 2026-05-31):* **stripped the false "EPA/Jayaratne" citation** and relabeled as an
   unvalidated humidity heuristic with an explicit do-not-use-for-AQI/health caveat (value-neutral).

## Data-quality rules (canonical: `docs/DATA-LIFECYCLE.md` §7)

- Drop `-999.0` sentinels, negatives, suspicious exact-zeros, stuck/repeated values; assert µg/m³;
  dedupe `(station, parameter, ts)`; keep reference-grade vs low-cost distinguishable (don't average
  blindly). pm25-only `value >= 500` fill-code guard (station 7440 = 985.0), not applied to pm10.
- **Outlier station `6273386`** (VNUHCMUS Campus 1, HCMC) excluded downstream (`is_outlier_station=1`).
- **Timezone trap:** `measurement_date` is local (+07:00) and correct for date-grouped daily marts;
  `measured_at` is UTC-rebased — a trap for any sub-daily logic.

## Source docs

- Research method (Lanes 2 & 4): `docs/RESEARCH-WORKFLOW.md`
- Data Description / DQ issues: `docs/workshop/5.1-introduction.md`
- DQ gate table (where rows drop & why): `docs/DATA-LIFECYCLE.md` §7
- Roster + source contract: `CLAUDE.md`

## Source code

`transform/models/staging/stg_measurements.sql`, `int_measurements_enriched.sql`,
`mart_daily_air_quality.sql`, `mart_health_summary.sql`, `transform/seeds/vn_stations.csv`,
`transform/models/marts/schema.yml`.

## Update triggers

Standard revision (EPA/WHO/QCVN), correction-formula change, DQ-rule change, new outlier station.
Every domain claim must cite the standard AND be verified against live data before it's trusted.

# PLAN — Fix the `corrected_pm25` false-citation / wrong-physics defect (Fix #3 minimum)

- **Date**: 2026-05-31
- **Complexity**: COMPLEX (correctness-critical; touches a mart + two downstream forecast-layer marts + schema docs)
- **Status**: ACTIVE — PLAN phase complete; awaiting EXECUTE approval
- **RIPER-5 phase**: PLAN. **Do not write code from this document** — each phase has a PAUSE gate.
- **Context router**: `process/context/all-context.md`; verification gates from `process/context/tests/all-tests.md`.
- Calibrated against `process/context/planning/example-complex-prd.md` and `all-planning.md`.

---

## Phase Completion Rules

- Each phase below ends with an explicit **✅ VERIFIED** gate and a **⏸ PAUSE**. A phase is complete only
  when its gate evidence is captured AND the user confirms (says `go`) — `✅ VERIFIED` requires
  **user confirmation**, not self-assertion. Do **not** start the next phase until then.
- Phase 0 is a read-only live-probe RESEARCH **HARD GATE**: claims about deployed data are settled by an
  AWS probe (`process/development-protocols/live-state-verification.md`), not inferred.
- No file is edited before the Phase 0/1 PAUSE returns explicit `go`.

---

## 1. Context and Goals

`transform/models/marts/mart_daily_air_quality.sql` ships a `corrected_pm25` column for low-cost PM2.5
sensors that is **falsely attributed and non-physical**:

- **False citation.** The code and docs attribute the formula to "EPA/Jayaratne" — at
  `mart_daily_air_quality.sql:96-97` (CTE comment), `:202` and `:208` (inline comment block), and
  `schema.yml:141` (`mart_daily_air_quality`), `:796` (`mart_aq_weather_daily`), `:872`
  (`mart_lagged_features`). Per `process/context/domain-data-quality/all-domain-data-quality.md:27-47`,
  **no Jayaratne or EPA correction of the algebraic form `1/(1+0.24·RH)` exists**; Jayaratne 2018
  (AMT 11:4883) documents RH over-reading but publishes no such formula, and the `0.24` constant
  traces to no source.
- **Wrong physics.** True hygroscopic-growth correction is nonlinear (κ-Köhler:
  `PM_dry = PM_wet/(1 + κ/(100/RH − 1))`, diverging as RH→100%). A linear divisor
  `raw / (1 + 0.24·RH_fraction)` (deployed at `mart_daily_air_quality.sql:211-222`) cannot capture this.
- **Stale, contradictory header.** The SQL header at `mart_daily_air_quality.sql:34-39` describes a
  **different, dead formula** — a flat `corrected = avg_value / 1.50` ("~50% overestimate"). This
  contradicts the `/(1+0.24·RH)` code that actually runs. (New defect surfaced in research; not in the
  domain doc. The inline block at `:201-209` was independently updated to the RH formula but the
  header was never reconciled.)

**Goal (Fix #3 minimum, the chosen scope):** remove the false-provenance liability and the physics
overclaim with a **comment- and schema-string-only** edit — strip the "EPA/Jayaratne" attribution
everywhere, relabel `corrected_pm25` as an **unvalidated humidity heuristic** with an explicit
**do-not-use-for-AQI/health-reporting** caveat, and reconcile the stale `/1.50` header against the
deployed `/(1+0.24·RH)` formula. **The relabel-vs-drop choice is resolved in §7 (Decision D-1): RELABEL.**

## 2. Non-goals

- **Not** implementing the validated **Barkjohn US-PurpleAir** correction (Fix #1) or a **κ-Köhler
  local-κ** form (Fix #2). Both require a Vietnam reference+low-cost collocation campaign and `PA_cf1`
  raw-channel data that neither this roster nor OpenAQ provides — **out of envelope, deferred long-term.**
- **Not** changing the numeric computation of `corrected_pm25`. The divisor stays
  `/(1+0.24·coalesce(avg_rh,70.0)/100.0)`. This is a **provenance/labeling fix, not a value change.**
- **Not** wiring `corrected_pm25` into any AQI/health path. It stays an unconsumed passthrough column;
  the caveat exists precisely to keep it that way.
- **Not** dropping the column (decision D-1 below selects relabel; drop is the rejected alternative).
- **Not** touching Terraform, Lambdas, alarms, the API, or any infra.

## 3. Constraint-Envelope Check (RESEARCH-WORKFLOW Lane 5 — hard filter)

Pass/fail against the standing filter (≤ ~$3–8/mo · single operator · serverless/scale-to-zero ·
~5 reporting stations · local TF state deliberate · QuickSight gated):

| Constraint | This change | Verdict |
|---|---|---|
| ≤ ~$3–8/mo | Comment + YAML-string edits; one `dbt run --select` of one mart family to re-stamp metadata. No new infra. Marginal Athena CTAS cost is a few cents, one-time. | **PASS** |
| Single operator | One author, local dbt; no concurrency. | **PASS** |
| Serverless / scale-to-zero | No runtime component added. | **PASS** |
| ~5 reporting stations | Touches only the 2 active low-cost non-outlier stations' column metadata; no roster change. | **PASS** |
| Reversible / low blast | Comment/string-only; `git revert` + one `dbt run` restores prior state. | **PASS** |

**In-envelope. No out-of-envelope element.** (Fixes #1/#2 would fail this filter — correctly deferred.)

## 4. Blast Radius

| Surface | Touched? | What changes | Risk |
|---|---|---|---|
| `transform/models/marts/mart_daily_air_quality.sql` (header `:34-39`, CTE comment `:96-97`, inline block `:201-209`) | **yes** | strip false citation; reconcile `/1.50`→`/(1+0.24·RH)`; relabel as unvalidated heuristic + caveat. **Comments only** — `:211-222` compute logic untouched. | **low** — non-executing text |
| `transform/models/marts/schema.yml:141-145` (`corrected_pm25` desc) | **yes** | relabel description, drop "EPA/Jayaratne", add caveat | **low** — YAML string |
| `transform/models/marts/schema.yml:796` (`mart_aq_weather_daily.corrected_pm25`) | **yes** | same relabel | **low** |
| `transform/models/marts/schema.yml:872` (`mart_lagged_features.corrected_pm25`) | **yes** | same relabel | **low** |
| `mart_daily_air_quality` data values | **no** | divisor formula unchanged | **none** — values byte-identical |
| `mart_aq_weather_daily.sql:42,92` (passthrough consumer) | **no** | carries `corrected_pm25` as-is; no SQL edit | **none** |
| `mart_lagged_features.sql:61,95,175` (passthrough consumer) | **no** | carries `corrected_pm25` as-is; no SQL edit | **none** |
| Public AQI/API path (`mart_daily_aqi`, `aqi_api/handler.py:59-83`) | **no** | derives from raw `avg_value`; never selects `corrected_pm25` (verified) | **none** |
| `mart_health_summary` / `mart_exceedance_stats` | **no** | aggregate raw `avg_value` flags | **none** |
| Lambda tests (`lambda/tests/`, 85 pass) | **no** | no Lambda touched | **none** — run as guard only |
| dbt tests / freshness | **no new tests required**; existing generic tests on the mart still apply | re-run as guard | **low** |
| `DaysSinceLastNewMart` alarm (21d) | **no** | re-materializing the mart refreshes its timestamp — *helps*, not hurts | **none** |

**Net blast:** non-executing comment + YAML-string edits to one mart and three schema descriptions.
`corrected_pm25` has **no live consumer** today (forecast Lambda gated/absent per CLAUDE.md). The
asset protected is **provenance/scientific-integrity correctness**, not a live user-facing number.
**Rollback** = `git revert` the doc commit + one `dbt run --select mart_daily_air_quality` to re-stamp
(see §8).

---

## 5. Phased Delivery Plan

> Each phase ends with a concrete **✅ VERIFIED** gate and a **⏸ PAUSE** before code is written.
> Phase 0 is a **read-only live-probe RESEARCH HARD GATE** — claims about deployed data are settled by
> a probe against ground truth (`process/development-protocols/live-state-verification.md`), not inferred.

### Phase 0 — RESEARCH (read-only; HARD GATE)

Goal: lock the **pre-change baseline** so we can prove the edit is value-neutral (comment/string-only)
and re-confirm the blast-radius assumptions before touching anything. All steps are read-only.

1. **Confirm the deployed formula vs. the stale header.** Read `mart_daily_air_quality.sql:34-39`
   (header, `/1.50`), `:96-97`, `:201-222` (inline, `/(1+0.24·RH)`). Confirm the contradiction exists
   exactly as research states. (Code read, no execution.)
2. **Live Athena probe (workgroup `openaq_workgroup`):** capture the current `corrected_pm25` baseline:
   - Low-cost non-outlier PM2.5 station-day count (expect **262**: 6068138 = 60 days
     2025-10-09→12-08; 6123215 = 202 days 2025-11-08→2026-05-28).
   - Mean deflation `avg_value` vs `corrected_pm25` (expect **~11.68%**; implied divisor **1.08–1.17**,
     confirming real RH in use, not the 70% fallback).
   - Station means (expect 6123215 raw 66.88→corr 59.06; 6068138 raw 34.61→corr 30.82).
   - AQI-category flip count **if** `corrected_pm25` were used (expect **49/262 = 18.7%, all downward**).
     This is the latent-impact figure, captured for the record — *not* a value we are changing.
3. **Re-confirm `corrected_pm25` reaches no AQI/health verdict.** Read `mart_daily_aqi.sql:46,70`
   (selects raw `aqi_value` only) and `aqi_api/handler.py:59-83` (queries `mart_daily_aqi`); confirm
   `corrected_pm25` is not referenced. Grep `lambda/` and `dashboard/` for `corrected_pm25` (expect no
   matches). Confirm `mart_aq_weather_daily.sql:42,92` and `mart_lagged_features.sql:61,95,175` carry
   it only as a passthrough feature column (no health/AQI derivation).
4. **Confirm grep inventory of the false citation.** Grep `transform/` for `Jayaratne` and `EPA/Jay`
   to enumerate every occurrence so none is missed. Expected hits: `mart_daily_air_quality.sql` (header
   region + `:96-97`, `:202`, `:208`), `schema.yml:141`, `:796`, `:872`. Record the exact line set.

**✅ VERIFIED gate (HARD):** a written baseline pasted into this plan containing: (a) the 262-row count
+ mean deflation + station means + 49 downward flips from a live Athena query; (b) the confirmed
no-consumer evidence (mart/handler reads + empty greps); (c) the complete grep inventory of "Jayaratne"/
"EPA" occurrences. **Do NOT proceed to Phase 1 until every figure is backed by a probe result — not
inferred from SQL.** If the live row count, deflation, or consumer map diverges materially from the
research figures above, **stop and revise this plan here**, not mid-execution.

> ⏸ **PAUSE — research → implementation.** Present Phase 0 evidence and the §7 decisions (D-1 relabel,
> D-2 exact wording). Wait for explicit `go` before editing any file.

### Phase 1 — Reconcile the stale header + strip the false citation in the mart SQL

(Comment-only edits to `mart_daily_air_quality.sql`. No change to lines `:211-222` compute logic.)

1. **Header `:34-39`** — replace the dead `corrected = avg_value / 1.50` / "~50% overestimate" text
   with a description of the *actual* deployed formula `corrected = avg_value / (1 + 0.24·RH_fraction)`,
   explicitly labeled **unvalidated humidity heuristic — not a published/cited method**, with the
   do-not-use-for-AQI/health caveat.
2. **CTE comment `:96-97`** — remove "EPA/Jayaratne"; describe the RH CTE neutrally (it supplies
   station-day mean RH to an unvalidated heuristic).
3. **Inline block `:201-209`** — strip `:202` "EPA/Jayaratne humidity-adjusted formula" and `:208`
   "Reference: Jayaratne et al. 2018; AirGradient field study Hanoi 2023". Replace with: unvalidated
   linear humidity heuristic; `0.24` constant has no published provenance; not physically validated for
   Vietnam aerosol; **do not use for AQI or health reporting**; correct long-term fixes are
   Barkjohn-PurpleAir (post-collocation) or κ-Köhler (local-κ). Keep the factual notes that the
   correction is gated to `sensor_type='low_cost'` and that reference stations pass through unchanged.

**✅ VERIFIED gate:** `cd transform && dbt parse` succeeds (SQL still compiles — comments only).
Diff review confirms **only comment lines changed**; lines `:211-222` are byte-identical. No
"Jayaratne"/"EPA" string remains in `mart_daily_air_quality.sql` (grep returns zero).

> ⏸ **PAUSE.** Present the diff. Wait for `go` before Phase 2.

### Phase 2 — Relabel the three `schema.yml` descriptions

(YAML-string edits only.)

1. `schema.yml:141-145` (`mart_daily_air_quality.corrected_pm25`) — replace "Uses the EPA/Jayaratne
   humidity-adjusted formula" with: "Unvalidated linear humidity heuristic
   (`÷(1+0.24×RH_fraction)`); **not a cited/published method** and **not validated for Vietnam
   aerosol — do not use for AQI or health reporting**. Applied to `sensor_type='low_cost'` only;
   reference stations pass through unchanged (`= avg_value`). NULL for non-PM2.5."
2. `schema.yml:796` (`mart_aq_weather_daily.corrected_pm25`) — replace the one-line
   "EPA/Jayaratne humidity-adjusted PM2.5…" with the relabeled, caveated one-liner.
3. `schema.yml:872` (`mart_lagged_features.corrected_pm25`) — same relabel.

**✅ VERIFIED gate:** `cd transform && dbt parse` succeeds (valid YAML). Grep `transform/models/marts/`
for `Jayaratne` and `EPA/Jay` returns **zero** matches across both SQL and YAML.

> ⏸ **PAUSE.** Present the diff. Wait for `go` before Phase 3.

### Phase 3 — Re-materialize, verify value-neutrality, and run guard suites

1. **Lambda guard:** `python -m pytest lambda/tests -q` — expect **85 pass / 0 fail** (no Lambda
   touched; this proves no collateral regression).
2. **dbt compile + model test:** `cd transform && dbt parse` then
   `dbt test --select mart_daily_air_quality+` — expect green (the `+` pulls the two passthrough
   consumers `mart_aq_weather_daily`, `mart_lagged_features`; no new tests added).
3. **Re-materialize to refresh metadata** (optional but recommended to re-stamp the doc-persist and
   the mart timestamp): `cd transform && dbt run --select mart_daily_air_quality`.
4. **Live value-neutrality probe (Athena, `openaq_workgroup`):** re-run the Phase 0 baseline query and
   assert the **262-row count, mean deflation, and station means are byte-identical to Phase 0** —
   proving the edit changed *labels only*, not data.

**✅ VERIFIED gate:** `pytest lambda/tests` 85/0; `dbt test --select mart_daily_air_quality+` green;
live `corrected_pm25` figures identical to the Phase 0 baseline; zero "Jayaratne"/"EPA" strings in
`transform/models/marts/`.

> ⏸ **PAUSE.** Present final evidence for the definition-of-done sign-off.

---

## 6. Acceptance Criteria (Verification Summary / definition of done)

- [ ] Phase 0 live-probe baseline captured in this plan (262 station-days, ~11.68% deflation, station
      means, 49 downward flips) — each figure backed by a pasted Athena result.
- [ ] Phase 0 no-consumer evidence captured (`mart_daily_aqi`/`aqi_api` read raw `avg_value`; empty
      `lambda/` + `dashboard/` greps for `corrected_pm25`).
- [ ] Stale `/1.50` header at `mart_daily_air_quality.sql:34-39` reconciled to the deployed
      `/(1+0.24·RH)` formula.
- [ ] All "EPA/Jayaratne" / "Jayaratne et al. 2018" attributions stripped from
      `mart_daily_air_quality.sql` and `schema.yml` (grep = zero across `transform/models/marts/`).
- [ ] `corrected_pm25` relabeled as an **unvalidated humidity heuristic** with an explicit
      **do-not-use-for-AQI/health-reporting** caveat in the SQL and all three `schema.yml` descriptions
      (`:141-145`, `:796`, `:872`).
- [ ] Compute logic `mart_daily_air_quality.sql:211-222` **unchanged** (diff shows comments/strings only).
- [ ] `python -m pytest lambda/tests -q` → 85 pass / 0 fail.
- [ ] `cd transform && dbt parse` succeeds; `dbt test --select mart_daily_air_quality+` green.
- [ ] Live `corrected_pm25` row count + deflation **identical** to Phase 0 baseline (value-neutral).
- [ ] Domain doc `process/context/domain-data-quality/all-domain-data-quality.md` cross-checked —
      Fix #3 marked applied; Fixes #1/#2 left as documented future work.

## 7. Decisions resolved in PLAN

- **D-1 — Relabel vs. drop the column: RELABEL (keep `corrected_pm25`, fix its provenance).**
  Rationale: the two passthrough consumers (`mart_aq_weather_daily`, `mart_lagged_features`) already
  carry it as a feature column with valid `ref()` dependencies; dropping it requires editing
  `mart_aq_weather_daily.sql:42,92` and `mart_lagged_features.sql:61,95,175` and their schema entries —
  a **larger blast radius** that also discards a (clearly-caveated) candidate feature the gated forecast
  layer may legitimately A/B test later. Relabel achieves the P0 objective (kill the false provenance +
  the do-not-use caveat) at the **minimum** blast radius, which is the whole point of choosing Fix #3.
  *(Drop remains the rejected alternative; revisit only if a future audit wants zero unvalidated
  columns in the feature marts.)*
- **D-2 — Wording anchor:** the caveat must contain the literal phrase
  **"unvalidated humidity heuristic — not a cited method; do not use for AQI or health reporting"** so a
  future reader (or the forecast author) cannot mistake it for a validated correction. Exact final
  wording is reviewed at the Phase 0/1 PAUSE.

## 8. Rollback

- All edits are comment/YAML-string only and confined to two files. **`git revert <commit>`** restores
  the prior text exactly.
- If the optional `dbt run --select mart_daily_air_quality` (Phase 3 step 3) was executed, run it again
  after the revert to re-stamp the persisted metadata. The mart **values are unaffected either way**, so
  there is no data restoration to perform.
- No infra, IAM, alarm, or API change is made, so there is nothing to roll back outside `transform/`.

## 9. Open Questions

- **Final caveat wording** (D-2): exact one-liner for the three `schema.yml` descriptions and the SQL
  block — confirm at the Phase 0/1 PAUSE.
- **Does the domain doc need a status line update?** Confirm whether
  `all-domain-data-quality.md:41-47` should be annotated "Fix #3 applied <date>" as part of this cycle
  or tracked separately. (Default: annotate in-cycle; it is the system of record for this defect.)
- **Phase 0 divergence trigger:** if the live deflation/row-count differs materially from the research
  figures (e.g. the 70% RH fallback is now dominant, pushing the divisor toward 1.168), does that change
  any wording? (Expected: no — the relabel is provenance-only — but the gate forces an explicit check.)

---

## Backlog (deferred this cycle)

Ranked output from the prioritizer; only rank 1 (this plan) is in scope for this cycle.

| Rank | Item | Severity | In envelope | Disposition |
|---|---|---|---|---|
| 1 | **`corrected_pm25` false-citation/wrong-physics fix (Fix #3)** — this plan | P0 correctness | yes | **THIS CYCLE** |
| 2 | Tag the 3 built-but-unconsumed leaf marts (`mart_health_summary`, `mart_exceedance_stats`, `mart_annual_monthly_trend`) with `tags=['bi_disabled']`; reconcile the false `schema.yml:13-15` header comment | Cost/maintainability (low) | yes | **Defer** — good quick follow-on; few cents/mo; not correctness |
| 3 | Migrate local TF state → encrypted S3 backend (durability only: S3 + versioning + SSE + PAB-all-true + `use_lockfile`; **NO DynamoDB**) | Reliability (med) / Security (low) | yes (durability half) | **Defer (conditional)** — adopt only if operator workstation is **not** backed up out-of-band; else keep deliberate local-state stance. Resolve backup question first. |
| 4 | Add WAF to public API Gateway | Security (low) | **no** | **DECLINE** — WAFv2 ~$5+/mo floor rivals/exceeds the whole $3–8/mo budget for a read-only, no-input, public-data GET already bounded by throttle (burst 20/rate 10) + reserved_concurrency=10 + 1h cache + partition pruning. Accepted residual risk. |

**Also deferred (out-of-envelope, long-term):** Barkjohn US-PurpleAir (Fix #1) and κ-Köhler local-κ
(Fix #2) for `corrected_pm25` — both need a Vietnam reference+low-cost collocation campaign and
`PA_cf1` raw-channel data unavailable in this roster or via OpenAQ. **Do NOT add DynamoDB** for TF state
(superseded by TF 1.14 native `use_lockfile`). Verified-DONE items not to re-propose: batch_sync
per-station alarm, direct Lambda Errors/DLQ/throttle alarms, `DaysSinceLastNewMart`, weather alarm,
mart-expiry→`processed/`, source_code_hash, codebuild-source in TF, dual-secret removal, API
throttle+reserved-concurrency, dbt_runner Glue scope-down, dead AQI macro/`int_city_daily_pm25`
cleanup, Hive-vs-Iceberg (answered: Parquet CTAS).

---

## Touchpoints

| File | Lines | Edit |
|---|---|---|
| `transform/models/marts/mart_daily_air_quality.sql` | `:34-39`, `:96-97`, `:201-209` | comments only (citation strip + header reconcile + relabel); `:211-222` compute **untouched** |
| `transform/models/marts/schema.yml` | `:141-145`, `:796`, `:872` | relabel the three `corrected_pm25` descriptions |
| `process/context/domain-data-quality/all-domain-data-quality.md` | `:41-47` | annotate "Fix #3 applied 2026-05-31" (system of record for the defect) |

## Public Contracts

None changed. `corrected_pm25` stays the same column with byte-identical values (divisor unchanged); only
its documentation/provenance is corrected. No API, schema-shape, table-name, partition, or downstream
`ref()` contract changes. The two passthrough consumers (`mart_aq_weather_daily`, `mart_lagged_features`)
keep their existing dependency on the column.

## Verification Evidence

*(Filled during EXECUTE — captured at each phase gate.)*
- [ ] Phase 0 Athena baseline (262 station-days, ~11.68% deflation, station means, 49 downward flips) — pasted query results.
- [ ] Phase 1/2 diffs showing comment/string-only changes; `dbt parse` green; zero `Jayaratne`/`EPA` grep hits.
- [ ] Phase 3: `pytest lambda/tests` 85/0; `dbt test --select mart_daily_air_quality+` green; live re-probe identical to Phase 0 (value-neutral).

## Resume and Execution Handoff

This plan is the **primary execute anchor**; there are no supporting phase files. To begin EXECUTE, the
user gives `ENTER EXECUTE MODE` (or `go`); the executor starts at **Phase 0** (read-only HARD GATE),
pastes the baseline evidence here, then PAUSEs for confirmation before Phase 1. On completion, move this
file to `process/general-plans/completed/` and update the domain doc status line.
**Next step:** await `ENTER EXECUTE MODE`.

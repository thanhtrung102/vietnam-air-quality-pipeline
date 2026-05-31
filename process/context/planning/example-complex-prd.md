# Example Complex PRD — Add NO₂ AQI Sub-Index to the Daily Mart

> **This is a reference template, not an active plan.** It shows the depth, phasing, and verification
> rigor a COMPLEX `vc-generate-plan` output should match for this project. Copy the *shape*, not the
> content. A real plan would live in `process/general-plans/active/` as a date-stamped `_PLAN.md`.

---

## 1. Problem & Goal

The daily AQI mart (`mart_daily_aqi`) currently computes the US-EPA AQI from PM2.5 only. OpenAQ
reports NO₂ for several Vietnamese stations. Goal: add an NO₂ sub-index and fold it into the overall
AQI as `max(pm25_aqi, no2_aqi)`, without regressing PM2.5 behavior or the freshness SLA.

**Non-goals:** O₃/SO₂/CO sub-indices (separate backlog item); changing the serving API contract beyond
one additive field.

## 2. Constraint Envelope Check (RESEARCH-WORKFLOW Lane 5)

Pass/fail against the standing filter before any design: ≤ ~$3–8/mo · single operator · serverless ·
~5 reporting stations. NO₂ adds no new infra (reuses the existing staging→mart path), so it is
in-envelope. **Flag:** NO₂ coverage is sparse (confirm station-by-station in Phase 0; do not assume).

## 3. Blast Radius

| Surface | Touched? | Risk |
|---|---|---|
| `stg_openaq_measurements` | yes — stop filtering NO₂ out | medium: must keep the `-999.0` sentinel filter |
| `int_measurements_enriched` | yes — carry NO₂ rows | medium |
| `mart_daily_aqi` | yes — new `no2_aqi`, revised `overall_aqi` | **high: correctness-critical** |
| `aqi_api` Lambda + GeoJSON | additive field only | low |
| dbt tests + freshness | new `accepted_values`/range tests | low |
| Alarms / SLA | none | none |

Rollback: revert the mart model + `dbt run --select mart_daily_aqi --full-refresh`; the API tolerates
a missing field.

---

## 4. Phased Plan (each phase PAUSES for verification before the next)

### Phase 0 — RESEARCH (read-only; HARD GATE)

- Probe live Athena: which station_ids have non-sentinel NO₂ rows, and over what date range?
- Confirm OpenAQ NO₂ `units` (µg/m³ vs ppb) per station — the EPA NO₂ breakpoints are defined in **ppb**.
- Capture the current `mart_daily_aqi` row count and AQI distribution as a pre-change baseline.

**✅ VERIFIED gate:** a written table of NO₂-reporting stations + units + baseline row count, each
backed by a query result pasted into the plan. **Do NOT proceed to Phase 1 until this is settled by a
live probe — not inferred from the model SQL.**

> ⏸ **PAUSE — research → implementation.** Present Phase 0 findings and the unit-conversion decision.
> Wait for explicit `go` before writing any model code. If NO₂ units are mixed across stations, the
> conversion logic changes and the plan must be revised here, not patched mid-execution.

### Phase 1 — Staging & intermediate

- Stop dropping NO₂ in `stg_openaq_measurements`; keep the `WHERE value != -999.0` sentinel filter.
- Carry NO₂ through `int_measurements_enriched` with units normalized to ppb.

**✅ VERIFIED gate:** `dbt run --select stg_openaq_measurements+ --exclude mart_daily_aqi` succeeds;
spot-check 3 stations' NO₂ rows against the Phase 0 probe. Pause.

### Phase 2 — Mart logic

- Add `no2_aqi` via the EPA NO₂ breakpoint table (1-hour, ppb); set `overall_aqi = max(pm25_aqi, no2_aqi)`.
- Stations with no NO₂ that day fall back to PM2.5-only (NULL-safe `max`).

**✅ VERIFIED gate:** `dbt run --select mart_daily_aqi --full-refresh` + live row-count delta vs the
Phase 0 baseline (expect **same row count**, AQI ≥ previous per row). Pause.

### Phase 3 — Tests & serving

- Add `accepted_values`/range tests for `no2_aqi`; add a singular test asserting `overall_aqi >= pm25_aqi`.
- Surface `no2_aqi` in the `aqi_api` GeoJSON properties (additive, non-breaking).

**✅ VERIFIED gate:** `dbt test --select mart_daily_aqi` green; hit the live API and confirm the new
field plus unchanged existing fields.

---

## 5. Verification Summary (definition of done)

- [ ] Phase 0 live-probe evidence captured (stations, units, baseline)
- [ ] `pytest lambda/tests` green (aqi_api handler test updated)
- [ ] `dbt test --select mart_daily_aqi+` green
- [ ] Live `mart_daily_aqi` row count unchanged; `overall_aqi >= pm25_aqi` holds on a live sample
- [ ] Live API returns `no2_aqi` with existing fields intact
- [ ] `README.md` / `all-context.md` test counts and mart description updated if changed

## 6. Open Questions

- Are any NO₂ readings in ppb already, or all µg/m³? (resolved in Phase 0)
- Do we backfill historical NO₂ or only forward? (default: full-refresh backfill; confirm cost)

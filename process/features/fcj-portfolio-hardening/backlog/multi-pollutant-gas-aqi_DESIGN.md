# Backlog — Multi-Pollutant Gas AQI (design sketch, not yet actionable)

**Status:** Parked (DOCUMENT-AS-NON-GOAL per `completed/phase-04-remaining-features_DECISION_01-06-26.md`).
**Becomes actionable when:** VN roster gains stations that actually report NO₂/O₃/SO₂/CO at sub-daily
cadence, and a correct sub-daily mart is justified.

## Why it's not built now
EPA gas AQI requires unit + averaging-window handling the current daily-grain marts cannot do correctly:

| Pollutant | EPA AQI input | Window | Our data |
|---|---|---|---|
| O₃ | ppm | 8-hr (+1-hr for high) | µg/m³, daily |
| CO | ppm | 8-hr | µg/m³, daily |
| SO₂ | ppb | 1-hr | µg/m³, daily |
| NO₂ | ppb | 1-hr | µg/m³, daily |

## Design if/when actionable (in-envelope shape)
1. **Unit conversion** µg/m³→ppb/ppm: `ppb = (µg/m³) × 24.45 / MW` at 25 °C / 1 atm (MW: O₃ 48, NO₂ 46,
   SO₂ 64, CO 28). Add as a staging transform keyed on `parameter`.
2. **Sub-daily mart**: a new `int_*_subdaily` model aggregating raw stream/batch to 1-hr means, then
   8-hr rolling for O₃/CO and 1-hr max for NO₂/SO₂ — only for stations that report each gas.
3. **Sub-index + composite**: per-pollutant AQI via the EPA gas breakpoint tables; composite =
   max(PM sub-indices, gas sub-indices). Keep gases NULL where unreported (no fabrication).
4. **Tests**: extend `unit_tests.yml` with gas-breakpoint unit tests (same pattern as PM).
5. **Cost gate**: the sub-daily mart scans more raw data — measure scan bytes before enabling; keep
   behind a `tag:` exclusion if material.

Until steps 1–2 are justified by real gas-reporting stations, the daily composite stays PM2.5/PM10 only.

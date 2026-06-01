# FCJ Portfolio Hardening — Umbrella / Orchestration Plan

**Date:** 01-06-26 (2026-06-01)
**Type:** Phase program (`process/development-protocols/phase-programs.md`)
**Status:** 🔨 ACTIVE — program layer
**Goal:** Bring the Vietnam Air Quality pipeline to a cohesive, verified, FCJ-portfolio-ready state —
implement the remaining in-envelope features/proposals and reconcile all docs + process/harness files —
without fragmenting the SDLC across scattered one-off plans.

This umbrella consolidates work that was previously filed as separate `general-plans/` cycles into one
program thread. Each unit of work is a **phase** with its own validation gate; durable evidence lives in
`reports/`, research in `references/`.

## Constraint envelope (standing filter)
≈ $3–8/mo · single operator · serverless/scale-to-zero · QuickSight Standard (BI gated → static
dashboard) · ~5 active stations · remote S3 Terraform state (native lockfile, no DynamoDB).

## Touchpoints
`transform/` (dbt models/tests), `lambda/`, `terraform/`, `docs/`, `dashboard/`, `process/context/`,
`process/general-plans/completed/`, `.claude` + `.codex` + `.agents` harness mirrors.

## Public Contracts
API GeoJSON (`GET /`) + `GET /analytics/{dataset}`; dbt mart schemas; the 84-test dbt suite;
Terraform resource set (~83). No breaking changes to these without an explicit phase.

## Blast Radius
Doc/process reconciliation is non-runtime. Feature builds (if any) touch dbt marts + Athena scans —
gated by the dbt test suite + a live CodeBuild run before any "done" claim (live-state HARD GATE).

## Phases

| # | Phase | Status | Evidence / pointer |
|---|---|---|---|
| 01 | L4 data-quality test breadth (unit tests + dbt-expectations + DATA-QUALITY.md) | ✅ VERIFIED | `general-plans/completed/l4-data-quality-hardening_PLAN_2026-06-01.md`; CodeBuild 84/84; commit `192b8af` |
| 02 | Well-Architected grounding (6 pillars + Data Analytics Lens) + AWS Budget | ✅ VERIFIED | `docs/WELL-ARCHITECTED.md`; budget live (`aws budgets describe-budgets`); commit `192b8af` |
| 03 | Dashboard HCMC map-vs-analytics UX reconciliation | ✅ VERIFIED | live site notes confirmed; commit `fdda4b2` |
| 04 | Remaining features / proposals decision + build | ✅ VERIFIED | `completed/phase-04-remaining-features_DECISION_01-06-26.md` (0 builds — none in-envelope+correct; 2 non-goals, 4 defers, 5 declines; gas-AQI design → `backlog/`) |
| 05 | Cleanup sprint — reconcile all docs + process/harness files; re-green the 13 kit validators | ✅ VERIFIED | `reports/phase-05-cleanup-sprint_REPORT_01-06-26.md` (12/12 validators PASS pre+post; forecast-live drift fixed across 6 docs) |

**Program status: ✅ COMPLETE** — all phases verified. Remaining work is intentionally deferred
(triggers recorded in phase-04 decision) or parked in `backlog/`. No in-envelope active work remains.

Phases 01–03 are retro-filed (completed before this folder existed); their authoritative plan
artifacts remain in `process/general-plans/completed/` — not duplicated here.

## Per-phase loop (required, per phase-programs.md)
research → approval → execute → validate → regression check → durable capture → commit →
inter-phase UPDATE PROCESS → move-on. Re-research at each phase entry.

## Verification Evidence
- Phase 01: CodeBuild `openaq-dbt-runner` → `PASS=84 WARN=0 ERROR=0 / 84` (2026-06-01).
- Phase 02: `aws budgets describe-budgets` → `openaq-pipeline-monthly` $8 COST.
- Phase 03: live dashboard strings confirmed served.
- Phases 04–05: pending (Workflow findings + validator re-run).

## Resume and Execution Handoff
- Open work = Phase 04 (features decision) + Phase 05 (cleanup sprint). Both seeded by background
  Workflow `wf_17b63ee0-a94` (research + audit fan-out). On completion, write its findings to
  `references/workflow-findings_<date>.md`, then create direct phase plans `phase-04-*` and
  `phase-05-*` in this `active/` folder and execute per the per-phase loop.
- Backlog (deferred-but-actionable) lives in `process/features/fcj-portfolio-hardening/backlog/`.
- Next valid state after each phase: `ENTER UPDATE PROCESS MODE` (archive + context capture) or keep
  in `active/` for more validation.

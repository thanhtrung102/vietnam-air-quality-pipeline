# FCJ Internship Report Site — Phase Program Plan

**Date:** 01-06-26 · **Type:** Phase program (`process/development-protocols/phase-programs.md`)
**Goal:** A web-deployable Hugo site (same generator + `hugo-theme-learn` + AWS visual format as the
FCJ reference `danielleit241.github.io/aws-fcj-report`) presenting this project as an FCJ internship
report. Fill **Proposal** + **Workshop** with reproducible, verified content; leave the other 5 of the
7 sections as placeholders. English only. AWS-format architecture diagram. Lives in `report/`.

## Reference format (verified by inspection)
FCJ report 7 sections: 1 Worklog · 2 Proposal · 3 Translated Blogs · 4 Events Participated ·
5 Workshop · 6 Self-Assessment · 7 Sharing & Feedback. Generator: **Hugo + hugo-theme-learn**,
sidebar nav, GitHub Pages. Workshop template (`aws-workshops`) = same stack, hierarchical 5.x sections.

## Source of truth for content (capturing project progress — already in the repo)
- Proposal ← `docs/BUSINESS-CONTEXT.md`, `docs/PIPELINE-REPORT.md`, `docs/WELL-ARCHITECTED.md`,
  `docs/DEPLOYED-SPECS-AND-AUDIT.md`.
- Workshop ← `docs/workshop/5.1–5.6.md` (English only), `docs/DATA-LIFECYCLE.md`, `docs/DATA-QUALITY.md`.
- Progress artifacts ← `process/features/fcj-portfolio-hardening/{completed,reports}` + `process/general-plans/completed/`.
- AWS diagram ← `docs/architecture.png` (awslabs diagram-as-code, AWS icons) + `docs/architecture.yaml` source.

## Phases
| # | Phase | Status |
|---|---|---|
| 01 | Scaffold Hugo + theme submodule + AWS-variant config | ✅ |
| 02 | Proposal section (problem/objectives/architecture/services/cost/success/reproducibility) | ✅ |
| 03 | Workshop section (landing + 5.1–5.6 reproducible runbook, English) | ✅ |
| 04 | Placeholders for sections 1,3,4,6,7 | ✅ |
| 05 | AWS diagram asset + deploy workflow (GitHub Pages) | ✅ |
| 06 | Verify: `hugo` builds clean; content reproducibility matches verified live state | ✅ |

## Outcome (commit `d1803ee`, 01-06-26)
- **Theme swap:** `matcornic/hugo-theme-learn` calls `.Site.IsMultiLingual` (removed in Hugo 0.158+) →
  swapped to its maintained successor **`McShelby/hugo-theme-relearn`** (same Learn-theme family/look).
  Full-history submodule clone OOM'd on this box; **`--depth 1` shallow add** succeeded.
- **Build green:** `hugo --gc --minify -s report` → 29 pages, exit 0. Only 4 residual warnings, all from
  relearn's own templates (`.Language.LanguageCode`, `.Site.Sites`) — upstream, harmless. Verified output:
  all 7 section dirs, 6 workshop subpages, Mermaid block in proposal, `images/architecture.png` (355 KB).
- **AWS palette** via `report/layouts/partials/custom-header.html` (Squid Ink / Smile Orange / link blue).
- **Architecture audit:** fixed 4 label drifts in `docs/architecture.yaml` (weather 300→900 s, CodeBuild
  85→84 dbt tests, monitoring 4→14 alarms, billing node → AWS Budget). CI regenerates the AWS-icon PNG
  from this audited source; proposal also carries an audited inline Mermaid diagram.
- **Deploy:** `.github/workflows/deploy-report.yml` (submodules recursive, awsdac regen, Hugo build → Pages).

## Verify (HARD GATE)
- `hugo --gc --minify -s report` builds with 0 errors; all 7 sections render in the sidebar.
- Proposal + workshop claims trace to verified live state (this session: 84/84 dbt, forecast live,
  budget live, API/dashboard 200) — no fabricated reproducibility.

## Reproducible deploy
GitHub Actions builds `report/` and publishes to Pages (mirrors the reference repos' workflow).

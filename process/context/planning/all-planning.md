# Planning — Context Group Entry Point

Quick router for **how this project plans work** under RIPER-5. This is the `planning/` context group
entrypoint (`process/context/planning/all-planning.md`). Read it before the PLAN phase, before
running the `vc-generate-plan` skill, or when calibrating the depth of a spec.

---

## Where Plans Live

Plans are durable artifacts on disk, not chat scrollback:

| State | Location | Meaning |
|---|---|---|
| Active | `process/general-plans/active/` | work in progress; one plan owns the current cycle |
| Completed | `process/general-plans/completed/` | archived, searchable decision history |
| Backlog | `process/general-plans/backlog/` | deferred ideas — check before duplicating |
| Reports | `process/general-plans/reports/` | execution/validation outputs |
| References | `process/general-plans/references/` | research that informs future plans |
| Feature-scoped | `process/features/{feature}/{active,completed,backlog,reports,references}/` | when work is large enough to warrant its own lifecycle folder |

**Naming:** `{slug}_PLAN_{YYYY-MM-DD}.md` — must contain the literal `_PLAN_` token **and** a date stamp
(both `vc-generate-plan`'s `validate-plan-artifact.mjs` and `vc-audit-plans` enforce this). See
`process/general-plans/active/fix-corrected-pm25-false-citation_PLAN_2026-05-31.md` for a worked example.

---

## Plan Depth: Simple vs Complex

`vc-generate-plan` produces two shapes. Calibrate against these:

- **Simple** — a single-surface, low-blast-radius change (one Lambda, one dbt model). Phases optional;
  a clear task list + verification gate is enough.
- **Complex** — multi-surface or correctness-critical (touches marts + serving, schema migrations,
  freshness/SLA). Use the worked template `process/context/planning/example-complex-prd.md` (referenced
  as `example-complex-prd.md`) to match the expected level of specificity: explicit phases, a
  research→implementation PAUSE gate, per-phase verification, and a blast-radius/rollback note.

Every complex plan must embed the **live-state-verification HARD GATE**: any claim about deployed AWS
or real data is settled by a read-only probe against ground truth before it enters the plan or a
"done" report (`process/development-protocols/live-state-verification.md`).

---

## Verification Gates In Plans

Pull concrete gates from the tests context group (`tests/all-tests.md`) — a plan's "done" criteria
should name the exact command and the live evidence required, not just "tests pass".

---

## Related Context

- The worked complex example: `process/context/planning/example-complex-prd.md`
- Verification gates and how to run the suite: `tests/all-tests.md`
- Shared workflow rules + phase lifecycle: `process/development-protocols/all-development-protocols.md`
- Root router: `process/context/all-context.md`

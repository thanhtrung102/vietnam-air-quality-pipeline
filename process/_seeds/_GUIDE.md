# process/_seeds — Bootstrap Template-of-Record

The skeleton `process/` structure the RIPER-5 harness expects. This project is already scaffolded
(`process/context/`, `process/general-plans/`, `process/development-protocols/`), so these seeds are
the reference template, not live state. Use them when re-bootstrapping process scaffolding or when a
new context group / plan folder is needed.

- `context/` — seed for a context group (each real group needs an `all-{group}.md` router).
- `general-plans/{active,completed,backlog,reports,references}/` — cross-cutting plan lifecycle.
- `features/_feature-template/` — per-feature lifecycle template.

Canonical instructions live at root `CLAUDE.md`, `AGENTS.md`, and
`process/development-protocols/all-development-protocols.md`. Skills live under `.claude/skills/vc-*`.

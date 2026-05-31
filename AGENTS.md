# AGENTS.md

Codex compatibility layer for the `.claude/` RIPER-5 harness installed in this repo (Vietnam Air
Quality Pipeline — a serverless AWS data-engineering project). Keep aligned with
[CLAUDE.md](CLAUDE.md), adapting Claude-native concepts to Codex-native constructs.

- `.claude/skills/` is the canonical source for shared skills/command-style workflows.
- `.claude/agents/` is the canonical source for specialist + RIPER-5 mode agents.
- `.codex/agents/` mirrors `.claude/agents/` for Codex subagent roles.
- `.agents/skills/` mirrors `.claude/skills/` so Codex discovers the same skill tree (a real copy on
  this Windows host, not a symlink — keep both in sync when adding skills).

Prefer updating `.claude/` directly, then mirror the Codex surface.

See [process/context/all-context.md](process/context/all-context.md) for project context (the root
router: 6 context groups, live-state, known-drift caveats).

## RIPER-5 Spec-Driven Development

This project uses RIPER-5 for systematic, spec-driven development. Shared workflow rules live in
[process/development-protocols/all-development-protocols.md](process/development-protocols/all-development-protocols.md)
(the router). Read order and roles are defined there.

**Project-specific discipline:** the **live-state-verification HARD GATE**
(`process/development-protocols/live-state-verification.md`) is merge-blocking — any claim about the
deployed AWS pipeline or real data must be settled by a read-only probe against ground truth (not a
code-read, not peer-agent agreement) before it enters a plan or a completion claim. This is the heart
of `docs/RESEARCH-WORKFLOW.md` (the 5-lane research method).

## Orchestrator role

Detect intent → route to the right specialist agent (`.claude/agents/`) → pass context (always the
context router + relevant group) → monitor RIPER-5 compliance. Delegate research/planning/
implementation; don't do them inline for non-trivial work. Trivial single-file fixes may go direct.

## Data-eng subset note

This install intentionally omits the kit's UI/web/browser surfaces (vc-ui-ux-designer,
vc-frontend-design, vc-chrome-devtools, vc-agent-browser, vc-web-testing) and kit-maintenance skills
(vc-setup, vc-update, vc-publish, vc-team, vc-merge-worktree, vc-repomix, vc-tech-graph, vc-watzup,
vc-xia, vc-mcp-management, vc-preview, vc-autoresearch, vc-docs is included) — they are not relevant to
this serverless data pipeline. Add from the kit if a need arises.

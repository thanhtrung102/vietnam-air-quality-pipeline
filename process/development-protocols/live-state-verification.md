# Live-State Verification (Refute the Hypothesis)

The HARD GATE for any claim about a deployed system, real data, or runtime behavior. Applies in every
mode but is **merge-blocking** before a finding enters a PLAN or an EXECUTE step claims completion.

## The rule

**Any claim that something is a bug, is broken, is correct, or that a number/format/timezone is X — about
a deployed system or real data — must be settled by a read-only probe against the real production state
BEFORE it informs a recommendation, plan, or completion claim.**

- A code-read is not verification (cast/format/timezone semantics are non-obvious; code can lie about
  runtime reality).
- A synthetic or literal probe is not enough (it may not match the real data's shape).
- **Another agent agreeing is not verification.** Confident agreement between agents that both reasoned
  from the same code reproduces the same blind spot. Verify against ground truth, not against each other.

## Why this exists (failure mode)

Multi-agent systems fail when agents recursively validate each other's reasoning instead of checking
reality — a shared-model "monoculture" reproduces the same error in the planner and the verifier. The
mitigation is verification against **sources / ground truth**, not peer consensus.

Worked example (this project): a fan-out's recon agent **and** its adversarial-verify agent both reasoned
from code and endorsed a "fix" to a date column. A live probe against real `+07:00` data showed the fix
would have corrupted **411,190 rows (29%)**. Two agents agreed; both were wrong; only the real-data probe
caught it.

## What counts as ground truth

- **Deployed cloud state:** `aws ... describe/list/get` (Lambda config, schedules, alarms, IAM), not the
  repo's IaC (state drifts from code).
- **Real data:** a read-only query against the actual table/partition (e.g. `aws athena` / a `SELECT`),
  returning the real value/format — not a synthetic example.
- **Runtime behavior:** the actual command/test output, the real HTTP response, the real log line.
- **Authoritative external standard** (for domain-correctness claims): the cited spec itself (EPA/WHO/
  RFC/vendor doc), quoted — not the agent's memory of it.

## Procedure

1. State the hypothesis explicitly ("`measurement_date` is UTC-shifted and wrong").
2. Design a read-only probe that could **refute** it against real state.
3. Run it; record the exact output as evidence (path/query/command + result).
4. Only a surviving hypothesis becomes a finding. A refuted one is discarded with its evidence.
5. Calibrate tests/gates to the **deployed control** they shadow (e.g. a freshness test threshold must
   match the deployed alarm), never to a guess; re-derive when the control changes.

## When it applies

- RESEARCH: every live-system / data / correctness claim before it enters the synthesis.
- PLAN: any assumption about current deployed state the plan depends on.
- EXECUTE: any "done / verified / works" claim about runtime or data — show the fresh evidence artifact.
- Cross-agent: a verifier subagent must check ground truth, not endorse another agent's narrative.

## Stack-neutral note

"Live state" = whatever the deployed reality is for this stack: cloud APIs, a running service, a
database, a built artifact. The discipline is identical; only the probe command changes.

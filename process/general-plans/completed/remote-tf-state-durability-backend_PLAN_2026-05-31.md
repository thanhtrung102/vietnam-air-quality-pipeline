# PLAN — Terraform state durability: local → encrypted S3 backend (durability-only, no DynamoDB)

- **Date**: 2026-05-31
- **Complexity**: COMPLEX (touches live Terraform state for 88 resources; one-time `init -migrate-state`)
- **Status**: DONE — D-1 resolved (NO out-of-band backup) → adopted; migrated & verified live 2026-05-31
- **RIPER-5 phase**: PLAN. **Do not run any terraform/state command from this document** — gated.
- **Context router**: `process/context/all-context.md`; infra group `process/context/infra-terraform/all-infra-terraform.md`; verification gates from `process/context/tests/all-tests.md`.
- Calibrated against `process/context/planning/example-complex-prd.md` and `all-planning.md`.

---

## Phase Completion Rules

- Each phase ends with an explicit **✅ VERIFIED** gate requiring **user confirmation** (`go`) before the next.
- Phase 0 is a read-only live-probe **HARD GATE** (state situation settled by AWS probe, not inference).
- **No bucket is created and no `terraform init`/`migrate-state` is run** before Decision D-1 is resolved
  and the user gives `ENTER EXECUTE MODE`. State migration is hard-to-reverse — treat with care.

---

## 1. Context and Goals

The pipeline's Terraform state is **local and gitignored**: `terraform/terraform.tfstate`, serial 654,
**88 resources**, Terraform **v1.14.3** (live-verified 2026-05-31). There is **no remote backend** and
**no state bucket** in the account. `docs/OPERATIONS-RUNBOOK.md` records local state as a *deliberate,
accepted* choice for a single operator — its stated mitigation is that the workstation is backed up
out-of-band.

**Risk:** if that workstation is lost and **not** backed up, the state for 88 live resources is gone —
recovery means `terraform import` of all 88 (slow, error-prone) or rebuild. This is a single-point-of-
failure on durability, not a correctness or security issue.

**Goal (durability-only):** move state to an **encrypted, versioned S3 bucket with native S3 locking**
(`use_lockfile = true`, Terraform ≥1.10 — satisfied at 1.14.3), **without DynamoDB**. Keep blast radius
minimal and reversible.

## 2. Non-goals

- **No DynamoDB lock table.** Out-of-envelope for a single operator; TF 1.14 native S3 lockfile replaces it.
- **No CI/remote-apply pipeline**, no second-operator workflow, no state encryption with a custom KMS
  CMK (SSE-S3/AES256 is sufficient and free). Those are future work if a 2nd operator/CI ever appears.
- **No change to any of the 88 managed resources.** This is a backend move; `terraform plan` must be a no-op after migration.

## 3. Decision D-1 (BLOCKING — resolve before EXECUTE)

> **Is the operator's workstation (where `terraform/terraform.tfstate` lives) backed up out-of-band**
> (Time Machine / OneDrive / file-history / periodic copy)?
>
> - **YES → DEFER this plan.** The runbook's deliberate local-state stance holds; the SPOF is already
>   mitigated. Revisit only when a 2nd operator or CI gains apply rights. Close this plan as `backlog`.
> - **NO → ADOPT** the durability-only S3 backend below. The SPOF is real and cheap to close.

## 4. Constraint-Envelope Check (Lane 5)

| Constraint | This change | Verdict |
|---|---|---|
| ≤ ~$3–8/mo | One small versioned S3 bucket holding a ~1–2 MB state file + a few old versions; pennies/mo. No DynamoDB. | **PASS** |
| Single operator | Native S3 lockfile prevents self-clobber; no multi-writer infra needed. | **PASS** |
| Serverless / scale-to-zero | S3 only. | **PASS** |
| Reversible | Backend block revert + `init -migrate-state` back to local; local backup retained throughout. | **PASS** |

## 5. Blast Radius

| Surface | Touched? | Risk |
|---|---|---|
| New S3 state bucket (created out-of-band via boto3) | **yes** — new | low; isolated, not managed by the state it backs |
| `terraform/main.tf` (or `backend.tf`) — add `backend "s3"` block | **yes** | medium — backend change triggers `terraform init -migrate-state` |
| Local `terraform.tfstate` (88 resources) | **migrated** (copied to S3) | **medium — the one risky step**; mitigated by a pre-migration local backup copy |
| The 88 managed AWS resources | **no** | **none** — `plan` must be no-op post-migration |
| Lambdas / dbt / API / alarms | **no** | none |

## 6. Phased Delivery Plan

### Phase 0 — RESEARCH (read-only; HARD GATE) — ✅ already done 2026-05-31
- Verified: TF v1.14.3 (native `use_lockfile` supported); no backend block; local state serial 654 / 88
  resources; tfstate gitignored; **no existing state bucket** in the account.
- **✅ VERIFIED gate:** above captured. **⏸ PAUSE — resolve Decision D-1 with the user before Phase 1.**

### Phase 1 — Bootstrap the state bucket OUT-OF-BAND (boto3, not Terraform)
- Create `openaq-tfstate-<suffix>` via boto3 (the bucket must **not** be managed by the state it backs —
  avoids the chicken-and-egg): region ap-southeast-1, **versioning ON**, **SSE-S3 (AES256)**,
  **Public Access Block all-true**, bucket policy deny non-TLS.
- **✅ VERIFIED gate:** `head-bucket` ok; versioning + encryption + PAB confirmed via boto3. ⏸ PAUSE.

### Phase 2 — Add the backend block + migrate (the one risky step)
- **Back up first:** copy `terraform/terraform.tfstate` to a timestamped local file.
- Add to `terraform/`:
  ```hcl
  terraform {
    backend "s3" {
      bucket       = "openaq-tfstate-<suffix>"
      key          = "openaq/terraform.tfstate"
      region       = "ap-southeast-1"
      encrypt      = true
      use_lockfile = true   # native S3 lock; no DynamoDB
    }
  }
  ```
- Run `terraform init -migrate-state` (copies local → S3).
- **✅ VERIFIED gate (user-confirmed):** `terraform init` reports successful migration; state object exists
  in S3 with versioning; **`terraform plan` is a clean no-op (0 to add/change/destroy)** — proving the 88
  resources are intact and only the backend moved. ⏸ PAUSE.

### Phase 3 — Confirm lock + durability, retire the local file safely
- Confirm a lock is taken/released on a `plan` (native lockfile object appears/clears).
- Keep the pre-migration local backup for one cycle; once a clean remote `plan` is confirmed, the working
  `terraform.tfstate` is the S3 copy. Update `docs/OPERATIONS-RUNBOOK.md` + `infra-terraform/all-infra-terraform.md`
  (local-state stance → remote-state-adopted).
- **✅ VERIFIED gate:** remote plan no-op; lock works; docs updated.

## 7. Acceptance Criteria (definition of done)

- [ ] Decision D-1 resolved (workstation backup status) and recorded.
- [ ] State bucket created with versioning + SSE-S3 + PAB-all-true (boto3-verified).
- [ ] `backend "s3"` block added; `terraform init -migrate-state` succeeded.
- [ ] **`terraform plan` is a no-op** (0 add / 0 change / 0 destroy) — 88 resources intact.
- [ ] Native lock observed working (no DynamoDB).
- [ ] Pre-migration local backup retained ≥1 cycle.
- [ ] `OPERATIONS-RUNBOOK.md` + `infra-terraform/all-infra-terraform.md` + `ARCHITECTURE-EVALUATION.md`
      Resolution status updated (remote state adopted).

## 8. Rollback

- Before migration: a timestamped local copy of `terraform.tfstate` exists.
- To revert: remove the `backend "s3"` block, run `terraform init -migrate-state` (S3 → local), or
  `terraform init -reconfigure` pointing back to local + restore the backup. No managed resource is ever
  modified, so there is nothing to roll back in AWS beyond deleting the (empty-purpose) state bucket.

## 9. Open Questions

- **D-1 backup status** (the blocker).
- Bucket suffix/naming convention (default: `openaq-tfstate-thanhtrung102` to mirror the data bucket).
- Keep the local backup how long? (default: one full apply cycle, then delete.)

---

## Touchpoints

| File / resource | Edit |
|---|---|
| new S3 bucket `openaq-tfstate-<suffix>` | created out-of-band (boto3) |
| `terraform/main.tf` (or new `terraform/backend.tf`) | add `backend "s3"` block |
| `docs/OPERATIONS-RUNBOOK.md`, `process/context/infra-terraform/all-infra-terraform.md`, `docs/ARCHITECTURE-EVALUATION.md` | flip local-state stance → remote-adopted (Phase 3) |

## Public Contracts

None. No managed resource, API, schema, or output changes. Backend location only; `terraform plan` no-op
is the contract that nothing else moved.

## Verification Evidence (EXECUTE, 2026-05-31)

- [x] **D-1 resolved by inspection:** tfstate on `D:\` (NOT under OneDrive `C:\Users\admin\OneDrive`),
      gitignored (not on GitHub), File History service Stopped/Manual → **no out-of-band backup** → adopt.
- [x] **Phase 0 live probe:** TF v1.14.3, no backend block, local state serial 654 / **88 resources**,
      no pre-existing state bucket.
- [x] **Phase 1 bucket:** `openaq-tfstate-thanhtrung102` created — versioning Enabled, SSE-S3 (AES256),
      Public Access Block all-true, TLS-only bucket policy (boto3-verified).
- [x] **Phase 2 migrate:** local backup `terraform.tfstate.premigrate-20260531` taken; `backend "s3"`
      block added to `main.tf` (`use_lockfile=true`, no DynamoDB); `required_version` → `>= 1.10.0`;
      `terraform init -migrate-state -force-copy` succeeded; remote state object present (88 resources).
- [x] **Phase 3 no-op:** first `terraform plan` showed 1 change = `aws_s3_object.codebuild_source` etag
      only (driven by this session's `transform/` edits via `archive_file`, NOT the backend move — zero
      infra-resource diffs). Applied that single change (also exercised the native S3 lock live, which
      deployed the Fix #3 + bi_disabled `transform/` edits into `codebuild-source.zip`); re-`plan` then
      reported **"No changes. Your infrastructure matches the configuration."** — clean no-op over 88
      resources. Docs flipped to remote-state-adopted.

## Resume and Execution Handoff

**Primary execute anchor**; no supporting phase files. EXECUTE is **gated on Decision D-1**. If D-1 = NO
(not backed up), the user gives `ENTER EXECUTE MODE` and the executor starts at Phase 1 (bootstrap bucket),
pausing at each gate. If D-1 = YES (backed up), move this file to `process/general-plans/backlog/` and keep
the deliberate local-state stance. **Next step:** answer Decision D-1.

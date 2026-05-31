# Infrastructure (Terraform) — Context Group

Last updated: 2026-05-31. Router for all IaC. Parent: `process/context/all-context.md`.

## Scope

All `terraform/*.tf`, the Athena workgroup + enforcement decision, Glue partition projection, the
parked `_qs_disabled/` QuickSight, the Lambda build/package pipeline.

## Read when

Touching any `.tf`, the workgroup config, partition projection, the build/upload pipeline, or
re-enabling QuickSight.

## Quick facts

- **State:** local Terraform state (deliberate — single operator; see OPERATIONS-RUNBOOK). TF ≥1.5.0,
  AWS provider ~>5.0. tfstate serial 585 / ~80 resources.
- **Files:** `main.tf` (TF settings, S3 bucket/lifecycle/website, Athena workgroup, pipeline role,
  result-reuse `null_resource`), `glue_tables.tf` (raw external tables, partition projection),
  `kinesis.tf` (stream + Firehose), `lambda.tf` (role + 6 functions incl. gated forecast, schedules,
  DLQs), `monitoring.tf` (SNS + dashboard + 14 alarms), `secrets.tf`, `variables.tf`, `outputs.tf`.
- **Athena workgroup `openaq_workgroup`:** 10 GB scan cap + SSE_S3 as **defaults**, with
  `enforce_workgroup_configuration = false`. **Why false:** enforcement forces all query output
  (incl. dbt CTAS marts) under the workgroup location and rejects CTAS with explicit
  `external_location`, trapping marts under `athena-results/` 7-day expiry. Cap+SSE remain as defaults;
  bucket default SSE-S3 + $8 billing alarm backstop. (PIPELINE-REPORT §4, DATA-LIFECYCLE §6.)
- **Partition projection** on Glue raw tables → no `MSCK REPAIR`/`GetPartitions` cost; Athena-only.
  Watch the >50%-empty-partition rule (AWS docs): if station×hour grids go sparse, registered
  partitions beat projection.
- **dbt CodeBuild source** packaged via Terraform `aws_s3_object.codebuild_source` (redeploy via
  `-target=aws_s3_object.codebuild_source`).
- **`_qs_disabled/`** holds all `quicksight_*.tf` + `create_analysis.py` + definition JSON + re-enable
  README. **Not loaded by Terraform** (account is QuickSight Standard).

## Source docs

- As-deployed inventory + audit: `docs/DEPLOYED-SPECS-AND-AUDIT.md` (stale §0/§1 — see root drift note)
- Workgroup/enforcement narrative: `docs/DATA-LIFECYCLE.md` §6, `docs/PIPELINE-REPORT.md` §4
- Build-from-scratch: `docs/workshop/5.3-storage-catalog.md`
- Operate / deliberate non-changes: `docs/OPERATIONS-RUNBOOK.md`

## Source code

All `terraform/*.tf`, `terraform/_qs_disabled/`, `lambda/build.sh`.

## Known issues

- Live IAM was applied via AWS CLI (provider crashed intermittently in the build env); `lambda.tf`
  reconciled to match live policy → `terraform plan` from a stable host should be ~no-op.
- Athena query-result-reuse is a `null_resource` + CLI call (AWS provider ~>5.0 doesn't expose the
  attribute) — revisit when the provider adds it.
- `architecture.{yaml,png,drawio}` still encode the QuickSight + 6-Lambda topology (stale) — give them
  one canonical owner + regen note if reconciled.

## Update triggers

Any resource add/remove, workgroup/enforcement change, partition-projection change, QuickSight
re-enable. After apply: verify live (`aws ... describe`) before updating the inventory doc.

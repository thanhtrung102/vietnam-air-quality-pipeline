# Operations Runbook

> Operational procedures and deliberate "won't-do" decisions for the deployed pipeline.
> Companion to `DEPLOYED-SPECS-AND-AUDIT.md` (what's deployed) and `RESEARCH-WORKFLOW.md`
> (how changes are researched/verified). Last updated 2026-05-31.
> AWS account 703668403514 · region ap-southeast-1.

## Deliberate non-changes (out of the constraint envelope)

The project's constraint envelope (RESEARCH-WORKFLOW.md, Lane 5) is the adversarial filter for
every proposed change: **≤ ~$3–8/mo · single operator · serverless/scale-to-zero · ~5 actively
reporting stations.** Some commonly-suggested "best practices" are **intentionally not adopted**
because they solve a problem this deployment does not have. They are recorded here so they are not
re-proposed as gaps.

### Remote Terraform state — ADOPTED 2026-05-31 (durability-only S3 backend, NO DynamoDB)

- **What changed:** `terraform.tfstate` moved from local-only to an encrypted, versioned S3 bucket
  `openaq-tfstate-thanhtrung102` (`key = openaq/terraform.tfstate`) with **native S3 locking**
  (`use_lockfile = true`, Terraform ≥1.10). Backend block lives in `terraform/main.tf`. Migrated via
  `terraform init -migrate-state`; `terraform plan` verified a clean no-op (88 resources intact).
- **Why adopted:** the prior local-only state was a **single-laptop durability SPOF** — workstation
  inspection (2026-05-31) found the tfstate was on `D:\` (not under OneDrive), gitignored (not on
  GitHub), and File History was off, i.e. **not backed up out-of-band**. Versioned S3 removes that SPOF
  for pennies/mo (in-envelope).
- **DynamoDB still NOT adopted** (out-of-envelope): a lock table exists to stop *concurrent* applies from
  multiple operators/CI. This pipeline is single-operator, so there is no contention to prevent — and TF
  1.10+ native S3 `use_lockfile` already guards against self-clobber at zero standing cost. Revisit
  DynamoDB only if a 2nd operator / CI gains apply rights.
- **Bootstrap note:** the state bucket is created **out-of-band** (boto3, `terraform/postdeploy`-style),
  not managed by the state it backs, to avoid the chicken-and-egg. A pre-migration local backup
  (`terraform.tfstate.premigrate-*`, gitignored) is retained for one cycle.

## Procedures

### Rotate the OpenAQ API key

The OpenAQ API key is stored in AWS Secrets Manager and read at runtime by the ingestion Lambdas
(`streaming_producer`, `batch_sync`, `weather_ingest` as applicable) via the secret name — **no
key material is baked into code or Lambda env vars.** A rotation therefore needs no redeploy.

- **Secret name:** `openaq/api_key`
- **Secret ARN:** `arn:aws:secretsmanager:ap-southeast-1:703668403514:secret:openaq/api_key-wVn9Bh`

> Context: an earlier OpenAQ key was committed to a git-ignored `terraform.tfvars` and surfaced in a
> local grep. Treat that key as compromised and rotate it. (The Terraform `openaq_api_key` variable
> has since been removed; the key now lives only in Secrets Manager.)

**Steps** (requires a NEW key from the operator — cannot be completed autonomously):

1. **Obtain a new key** from the OpenAQ account portal (https://explore.openaq.org/ → account/API
   keys). Generate a new key; do **not** revoke the old one yet.
2. **Write it to Secrets Manager** (do not echo the value into the shell history / logs):
   ```bash
   aws secretsmanager put-secret-value \
     --secret-id openaq/api_key \
     --secret-string file://newkey.txt    # newkey.txt = raw key, deleted after
   ```
   Use a file, not an inline `--secret-string <key>`, so the key never lands in shell history.
   On Windows save `newkey.txt` as UTF-8 without BOM.
3. **No redeploy needed** — Lambdas fetch the secret at invocation. (If a function caches the secret
   for the life of a warm container, force-refresh by publishing a trivial config change or waiting
   for cold start; current handlers read per-invocation.)
4. **Verify** the new key works by invoking an ingestion path and checking for 200s / no 401s:
   ```bash
   aws lambda invoke --function-name openaq_batch_sync /tmp/out.json
   # then tail its CloudWatch logs for auth errors
   ```
   Confirm a fresh row lands (the `assert_batch_source_fresh` dbt test and the
   `DaysSinceLastNewMart` alarm both watch this downstream).
5. **Revoke the old key** in the OpenAQ portal only after step 4 succeeds.
6. **Delete** `newkey.txt`.

### Re-deploy the dbt transform (CodeBuild source)

The CodeBuild dbt source zip is **Terraform-managed** (`archive_file.codebuild_source` →
`aws_s3_object.codebuild_source`). After editing anything under `transform/`, re-upload by applying
that object, then trigger a build:

```bash
terraform -chdir=terraform apply -target=aws_s3_object.codebuild_source
aws codebuild start-build --project-name openaq-dbt-runner
```

Do **not** hand-zip/upload (the old manual `zip -r codebuild-source.zip` path drifts from Terraform).
Verify the live zip actually contains your change before trusting a build (download + inspect), and
always reconcile the build ID against `aws codebuild list-builds-for-project` (authoritative) — see
the live-verification discipline in RESEARCH-WORKFLOW.md.

## dbt source freshness on Athena — known limitation

`dbt source freshness` is **not** used (removed from `buildspec_dbt.yml`). dbt-athena computes
freshness from Glue metadata (`last_modified`) returned as a string, so it errors on every source
regardless of actual freshness ([dbt-athena #631](https://github.com/dbt-labs/dbt-athena/issues/631));
a non-blocking gate then masks it as a constant WARN. Freshness is instead enforced by the
query-based singular test `transform/tests/assert_batch_source_fresh.sql` (runs in the post_build
`dbt test` step) plus the deployed `DaysSinceLastNewMart` CloudWatch alarm.

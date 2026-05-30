# Operations Runbook

> Operational procedures and deliberate "won't-do" decisions for the deployed pipeline.
> Companion to `DEPLOYED-SPECS-AND-AUDIT.md` (what's deployed) and `RESEARCH-WORKFLOW.md`
> (how changes are researched/verified). Last updated 2026-05-31.
> AWS account 703668403514 · region ap-southeast-1.

## Deliberate non-changes (out of the constraint envelope)

The project's constraint envelope (RESEARCH-WORKFLOW.md, Lane 5) is the adversarial filter for
every proposed change: **≤ ~$3–8/mo · single operator · serverless/scale-to-zero · ~5 actively
reporting stations · local Terraform state.** Some commonly-suggested "best practices" are
**intentionally not adopted** because they solve a problem this deployment does not have. They are
recorded here so they are not re-proposed as gaps.

### Remote Terraform state (S3 backend + DynamoDB lock) — NOT adopted

- **What it would add:** an S3 bucket for `terraform.tfstate` + a DynamoDB table for state locking,
  replacing the current local `terraform.tfstate`.
- **Why it's declined:** DynamoDB state locking exists to stop *concurrent* applies from two or more
  operators/CI runners corrupting shared state. This pipeline is explicitly **single-operator**, so
  there is no concurrent-apply contention to prevent. Remote state also adds standing cost (a
  DynamoDB table) and a bootstrap chicken-and-egg (the backend bucket/table must exist before
  `terraform init`), against a ≤$3–8/mo envelope.
- **Residual risk accepted:** local state lives on one machine. Mitigation is operational, not
  architectural — the repo is the source of truth for *configuration*, and `terraform.tfstate` is
  git-ignored and should be backed up out-of-band if the workstation is not already backed up.
- **Revisit when:** a second operator or any CI/CD runner gains `terraform apply` rights. At that
  point concurrent-apply contention becomes real and remote state + locking becomes correct. This is
  the single trigger — adopt it then, not before.

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

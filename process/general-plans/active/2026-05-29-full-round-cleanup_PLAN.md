# Plan — Full-Round Cleanup & Improvements (P0→P2)

- **Created:** 2026-05-29
- **Repo:** vietnam-air-quality-pipeline
- **Source audit:** `docs/DEPLOYED-SPECS-AND-AUDIT.md`
- **Shape:** Phased program (3 phases), each gated for approval before execution.
- **Approved scope:** Everything (P0 security → P1 reliability → P2 maintainability).

## Execution-requirement legend
- `[code]` — file edits only, no AWS calls, no live impact.
- `[git]` — involves commits / history hygiene.
- `[apply]` — requires `terraform apply` against the live account (ap-southeast-1).
- `[aws]` — requires a manual AWS API action + credentials (e.g. `secretsmanager put-secret-value`).

> **Prerequisite note (per deployment policy):** This agent environment is not confirmed to hold
> AWS credentials for account 703668403514. `[apply]`/`[aws]` items will be prepared as code +
> exact commands; the developer runs the apply (or confirms the agent may, with creds available).
> `[code]`/`[git]` items can be done fully here.

---

## Phase 1 — P0 Security & truth-in-repo  (lowest risk, highest value)

**Goal:** remove credential-leak surface and make git HEAD match deployed reality. No change to
live pipeline behavior.

| # | Item | Type | Detail |
|---|---|---|---|
| 1.1 | Harden `.gitignore` | `[code]` | Add `*.tfstate.*` and `*.backup` patterns so timestamped state backups can't be committed. Verify with `git check-ignore`. |
| 1.2 | Remove stray state backup | `[code]` | Delete `terraform/terraform.tfstate.1776474110.backup` (serial 493, obsolete; superseded by serial 585). Confirm it was never committed (`git log --all -- <path>` → empty). |
| 1.3 | Remove API key from Lambda env | `[code]`+`[apply]` | In `lambda.tf` drop `OPENAQ_API_KEY = var.openaq_api_key` from streaming env; keep only `OPENAQ_SECRET_NAME`. Code change here; takes effect on next apply. |
| 1.4 | Populate Secrets Manager | `[aws]` | `aws secretsmanager put-secret-value --secret-id openaq/api_key --secret-string <key>`. Must run BEFORE 1.3's apply so streaming auth doesn't break. **Developer-run** (needs the real key). |
| 1.5 | Commit the QuickSight disable | `[git]` | Decide: commit `_qs_disabled/` move + `outputs.tf` comment-out so HEAD == reality. Move `terraform/create_analysis.py` + `quicksight_analysis_definition.json` into `_qs_disabled/`. Add `_qs_disabled/README.md` (why disabled + re-enable steps). |

**Verification:** `git check-ignore` passes for backups; `grep OPENAQ_API_KEY lambda.tf` shows only secret path; `terraform validate`; `terraform plan` shows only the env-var removal (no destroy of live data resources). **Sequencing guard:** 1.4 before 1.3-apply.
**Rollback:** all changes are git-reveritable; secret value retained in state backup until apply.

---

## Phase 2 — P1 Reliability / cost / accuracy

**Goal:** close test gaps, stop wasteful triggers, harden ingestion, fix metric correctness.

| # | Item | Type | Detail |
|---|---|---|---|
| 2.1 | Unit tests: batch_sync, kinesis_producer, weather_ingest | `[code]` | Mock boto3/requests (mirror existing tests). Cover `_validate_reading`, retry/backoff (429/5xx vs 4xx), `_put_batch_with_retry` partial failure, `_get_api_key` ladder, ETag-skip, date bucketing. |
| 2.2 | batch_sync SNS behavior | `[code]`+`[apply]` | Either parse the S3 key from the SNS message and sync only that station/month, OR drop the SNS subscription and keep the daily cron. (Recommend: drop subscription — simplest, removes full-sweep-per-object cost.) |
| 2.3 | DLQ for batch_sync | `[code]`+`[apply]` | Add SQS DLQ + `dead_letter_config` (mirror streaming). |
| 2.4 | Kinesis SSE | `[code]`+`[apply]` | `encryption_type=KMS` on `openaq_stream`. |
| 2.5 | Enforce Athena workgroup config | `[code]`+`[apply]` | `enforce_workgroup_configuration=true` so 10GB cutoff + SSE are real. |
| 2.6 | Forecast holdout RMSE | `[code]` | Rolling 1-step backtest instead of 30-step-ahead vs actuals. (Note: forecast Lambda is not deployed — code-only quality fix.) |
| 2.7 | `mart_forecast_accuracy` windows | `[code]` | Window over `actual_pm25 IS NOT NULL` rows only. |
| 2.8 | Parameter-aware staging filter | `[code]` | Replace global `value<500` with per-parameter ceilings (keep 985 fill-guard for pm25; allow higher pm10). |
| 2.9 | Athena result-reuse declarative | `[code]`+`[apply]` | Move off `null_resource` local-exec to managed workgroup config. |
| 2.10 | aqi_api row hardening + kinesis_producer SystemExit→ValueError | `[code]` | Wrap feature build in KeyError guard; raise ValueError in `_load_config`. |

**Verification:** `pytest lambda/tests` green; `dbt parse`/compile clean; `terraform validate` + `plan` reviewed before any apply.

---

## Phase 3 — P2 Maintainability / docs / housekeeping

**Goal:** single-source config, accurate docs, CI guardrails, remove cruft.

| # | Item | Type | Detail |
|---|---|---|---|
| 3.1 | Single-source station roster | `[code]` | Terraform `csvdecode(file(vn_stations.csv))` → `station_ids_csv`; drop hardcoded copies in `batch_sync`/`weather_ingest` (rely on injected env); document seed as the one source. |
| 3.2 | Fix CLAUDE.md | `[code]` | Remove false "clusters on parameter, location_id"; list all 6 Lambdas. |
| 3.3 | Reconcile QuickSight in docs/diagrams | `[code]` | Mark workshop 5.5.5 "Optional — requires QuickSight Enterprise"; update 5.1 deliverables / 5.3 outputs / 5.6 teardown; remove QS node from `architecture.yaml` (PNG auto-regens via CI). |
| 3.4 | Validation CI workflow | `[code]` | New `.github/workflows/validate.yml`: `terraform fmt -check` + `validate`, optional `tflint`, `dbt parse`, `pytest`. |
| 3.5 | Terraform-manage dashboard deploy | `[code]`+`[apply]` | `templatefile()` + `aws_s3_object` to render `aqi_api_url` into `index.html` and upload — removes `YOUR_API_GATEWAY_URL` footgun. |
| 3.6 | dbt dedup + macros | `[code]` | Extract `int_city_daily_pm25`; AQI-breakpoint macro; circular wind mean (or drop `avg_wind_dir`); decide `corrected_pm25`. |
| 3.7 | Gate orphan marts | `[code]` | Tag QuickSight-only/diagnostic marts; exclude from default build while QS off. |
| 3.8 | Remove cruft | `[code]` | `terraform/tfplan`, `terraform/aqi_api.zip`, `lambda/openaq_producer.zip`, stale `dashboard/demo_data.json` (regen or relocate), empty `.gitkeep`s. Trim `prophet` from `create_forecast_table.sql` projection. |

**Verification:** CI green on a test branch; `dbt build` succeeds with reduced mart set; docs read-through matches infra.

---

## Closeout
After each phase: report what changed / verified / unverified; offer git-manager for logical commits.
Final: update `docs/DEPLOYED-SPECS-AND-AUDIT.md` and `CLAUDE.md` to reflect the new state.

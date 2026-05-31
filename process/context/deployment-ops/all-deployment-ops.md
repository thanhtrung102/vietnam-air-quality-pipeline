# Deployment & Operations — Context Group

Last updated: 2026-05-31. Router for CI, monitoring, and runbooks. Parent: `process/context/all-context.md`.

## Scope

CI (`.github/workflows/`), CloudWatch monitoring/alarms, `completeness_check`, key rotation, dbt
redeploy, the gated subsystems (forecast, QuickSight), deliberate out-of-envelope non-changes.

## Read when

Touching CI, alarms, the completeness monitor, operational runbooks, key rotation, or the gated
forecast/QuickSight subsystems.

## Quick facts

- **CI:** `validate.yml` (terraform fmt/validate, pytest, dbt parse), `diagram.yml` (regen
  architecture PNG from `architecture.yaml`). CI is the machine-check for dbt parse (the dev host
  can't run it — Python 3.14/mashumaro).
- **Monitoring:** 14 CloudWatch alarms (per-function Errors, DLQ depth, Kinesis iterator age,
  `BatchStationFailures`, `WeatherIngestErrors`, `MissingStations`, `DaysSinceLastNewMart`, billing>$8,
  CodeBuild FailedBuilds). SNS email + billing topic in us-east-1.
- **`completeness_check`** (hourly) emits `MissingStations` + `DaysSinceLastNewMart`. Self-suppresses
  the missing-station alert when data is archive-stale (`is_archive_stale: true`).
- **Freshness SLA:** `DaysSinceLastNewMart` alarm fires at **21 days** — the canonical control that dbt
  freshness tests are calibrated against (see `transform-dbt`).
- **Gated subsystems:** `forecast_generate` (SARIMA container; deploys only with
  `forecast_lambda_image_uri`), QuickSight (`_qs_disabled/`, account is Standard). Both are
  one-variable-away by design — present as gated, never as live.

## Runbooks (canonical: `docs/OPERATIONS-RUNBOOK.md`)

- **OpenAQ key rotation:** secret `openaq/api_key`. *(Open item: the old key remains valid/exposed
  until rotated — runbook ready; rotation deliberately deferred.)*
- **dbt redeploy:** `terraform apply -target=aws_s3_object.codebuild_source` then start the build.
- **Deliberate non-change:** remote TF state NOT adopted (single operator).

## Source docs

- Operate: `docs/OPERATIONS-RUNBOOK.md`
- Quality / open items + resolution status: `docs/ARCHITECTURE-EVALUATION.md`
- Redeploy blockers history: `docs/PIPELINE-REPORT.md` §7
- Build/teardown: `docs/workshop/5.2-prerequisites.md`, `5.6-cleanup.md`

## Source code

`.github/workflows/`, `terraform/monitoring.tf`, `lambda/completeness_check/`,
`lambda/forecast_generate/` (gated).

## Open items (from ARCHITECTURE-EVALUATION resolution block)

- API throttle/WAF, remote state (declined), CI Glue scope-down (done). OpenAQ key rotation pending.

## Update triggers

Alarm add/change, CI change, runbook procedure change, gated-subsystem enable. Verify alarms live
(`aws cloudwatch describe-alarms`) after change.

# AWS Well-Architected Review — Vietnam Air Quality Pipeline

> Grounds the project in the **AWS Well-Architected Framework** (6 pillars) + the **Data Analytics
> Lens**. This is not a fresh audit — it re-frames the project's existing, *adversarially-verified*
> 8-lens evaluation (`ARCHITECTURE-EVALUATION.md`) and live resource inventory
> (`DEPLOYED-SPECS-AND-AUDIT.md`) against the canonical pillars. Every claim cites real IaC or a
> live-re-verifiable probe — same discipline as the rest of the repo (live-state HARD GATE).
>
> **Context:** AWS First Cloud Journey (FCJ) **portfolio/demo** (`BUSINESS-CONTEXT.md`), region
> `ap-southeast-1`, account `703668403514`. Standing **constraint envelope**: ≈ $3–8/mo · single
> operator · serverless/scale-to-zero · QuickSight Standard (BI gated → static dashboard) · ~5 active
> stations · remote S3 Terraform state (native lockfile, no DynamoDB). The envelope is *itself* a
> Well-Architected decision: it forces the "right-sized, stop-spending-on-undifferentiated-heavy-
> lifting" choices the framework rewards, and it is the lens through which every "accepted risk" below
> is justified.

## How the project's 8-lens review maps to the 6 pillars

| WA Pillar | Project lens(es) | Pillar score (from verified eval) |
|---|---|---|
| Operational Excellence | Observability + Maintainability | 3 → stronger / 4 |
| Security | Security | 3 |
| Reliability | Reliability | 3 |
| Performance Efficiency | Scalability + performance | 3 |
| Cost Optimization | Cost | 3 |
| Sustainability | (re-framed here — not separately scored before) | n/a |

**Overall ≈ 3.3 / 5 — strong portfolio-grade engineering with a few deliberately-accepted production
gaps.** Scores are the *post-adversarial-verification* values (a skeptic agent refuted/softened >half
the initial findings; see `ARCHITECTURE-EVALUATION.md` "What adversarial verification changed").

---

## 1. Operational Excellence

**Design principles applied — perform operations as code, make frequent small reversible changes,
anticipate failure, learn from operational events.**

| Practice | Evidence (codified / live) | Re-verify |
|---|---|---|
| Infra as code, single `terraform apply` | All resources in `terraform/*.tf`; dbt `codebuild-source.zip` packaged by Terraform (`archive_file`+`aws_s3_object`); Lambda `source_code_hash` so rebuilt zips redeploy | `terraform plan` (clean no-op) |
| Operations as code | dbt-on-Athena via CodeBuild; EventBridge Scheduler drives all 6 jobs; `postdeploy.sh` secret injection; `docs/OPERATIONS-RUNBOOK.md` | `aws scheduler list-schedules` |
| Telemetry | X-Ray active tracing on all Lambdas; 14 CloudWatch alarms; `openaq_pipeline` dashboard; `completeness_check` emits `MissingStations`/`DaysSinceLastNewMart` | `aws cloudwatch describe-alarms --alarm-name-prefix openaq` |
| Learn from events | The `BatchStationFailures` alarm **earned its keep on day one** — first run surfaced 5/5 active stations silently failing PutObject; root-caused + fixed (see ARCH-EVAL Resolution status) | git log |
| Consistent tagging | `local.common_tags` (`Project`, `ManagedBy`) applied to **every** taggable resource (`main.tf:55`) | `grep -c common_tags terraform/*.tf` |
| PR-gated CI | `.github/workflows/validate.yml` — `terraform fmt/validate`, `pytest` (85 Lambda tests), `dbt parse` | view Actions |
| Layered test strategy | generic + 4 singular + 2 unit + dbt-expectations + freshness alarm — see `DATA-QUALITY.md` | `dbt test` |

**Risks:** None High. *Medium (accepted):* from-zero deploy needs `bash lambda/build.sh` before the
first apply (documented in workshop 5.3); CI runs `dbt parse` not `dbt test` (real Athena cost gated
to the scheduled CodeBuild run, by design).

## 2. Security

**Apply security at all layers, protect data in transit/at rest, least privilege, automate, prepare.**

| Practice | Evidence | Re-verify |
|---|---|---|
| Encryption at rest | S3 AES256 + bucket-key SSE; Kinesis KMS (`alias/aws/kinesis`); Athena results SSE_S3; Terraform state SSE-S3 | `aws s3api get-bucket-encryption --bucket openaq-pipeline-thanhtrung102` |
| Encryption in transit | HTTPS-only API Gateway; AWS SDK TLS for all service calls | API GW endpoint |
| Secrets management | OpenAQ key in **Secrets Manager only** (`openaq/api_key`); plaintext env var removed; key kept out of state via `ignore_changes` + post-deploy injection | `aws secretsmanager describe-secret --secret-id openaq/api_key` |
| Least privilege | Runtime Lambda role scoped; CI `openaq_dbt_runner_role` scoped to `database/openaq_mart*`, `table/openaq_mart*/*`, `openaq_raw`, `default` (no account-wide wildcard) | read `lambda.tf` IAM blocks |
| Network/edge controls | API GW `$default` throttle **burst=20 / rate=10** + `reserved_concurrent_executions=10` on `aqi_api` (availability + blast-radius cap) | `aws apigatewayv2 get-stage` |
| Public surface minimized | S3 public policy scoped to `dashboard/*` only; API serves read-only public-data GeoJSON | `aws s3api get-bucket-policy` |

**Risks / accepted residuals:**
- *Accepted DECLINE — no WAF on the public API.* WAFv2's ~$5+/mo floor exceeds the entire ~$3–8/mo
  envelope for a read-only public-data GET; the throttle + reserved-concurrency already cap the
  availability/cost blast radius. Recorded as accepted risk, not an open gap.
- *Accepted DECLINE — no dedicated CloudTrail trail.* The account's default **Event history** already
  retains 90 days of management events at $0; a dedicated multi-region trail adds an S3 write stream
  (storage cost) out of envelope for a demo. Revisit if this becomes a multi-account/prod workload.
- *Low (gated):* the dbt CodeBuild role retains broad-ish Glue *read*; scoped for writes, exploitation
  gated behind prior in-account compromise.

## 3. Reliability

**Automatically recover from failure, scale horizontally, stop guessing capacity, manage change.**

| Practice | Evidence | Re-verify |
|---|---|---|
| Idempotency | dbt full-refresh CTAS marts are deterministic re-runs; batch_sync re-syncs by object key; partition projection means no partition-registration drift | `dbt build` row-count diff |
| Fault isolation / DLQs | `openaq_streaming_dlq` + `openaq_batch_sync_dlq` wired; DLQ-depth alarms | `aws sqs list-queues` |
| Silent-failure detection | `BatchStationFailures`, `WeatherIngestErrors`, and the **non-suppressed** `DaysSinceLastNewMart>21` mart-freshness alarm (the true "silently dead" signal) | `aws cloudwatch describe-alarms` |
| Durable state | S3 versioning ON; noncurrent-version lifecycle; **remote versioned/SSE-S3 Terraform state** with native lockfile (closed the single-laptop SPOF) | `aws s3api get-bucket-versioning` |
| Elastic scale | Kinesis ON_DEMAND; Lambda concurrency; Athena serverless — all scale-to-zero/auto | n/a |

**Risks / accepted residuals:** *Medium (by design):* DLQs are inert on the **synchronous scheduled**
hot paths (they fire only on async invoke) — softened by 30-min cadence + the direct Errors/freshness
alarms. *Medium (deferred):* full-refresh transform is the reliability/scale break-point at ~5–10×
history → incremental `insert_overwrite` when history exceeds 1–2 yr (premature now; ADR-logged).

## 4. Performance Efficiency

**Democratize advanced tech, go serverless, experiment, use the right tool, mechanical sympathy.**

| Practice | Evidence | Re-verify |
|---|---|---|
| Right-sized serverless | 6 Lambdas (256–1024 MB), Kinesis/Firehose, Athena, CodeBuild — no idle servers | `aws lambda list-functions` |
| Scan minimization | **Glue partition projection** on all 3 raw tables (no crawler); marts Parquet+snappy partitioned on `measurement_date`; Athena 10 GB per-query cutoff | `aws athena get-work-group --work-group openaq_workgroup` |
| Mechanical sympathy | arm64 (Graviton) Lambdas; GZIP Firehose (128 MB/300 s buffer); `/tmp` response cache in `aqi_api` | function `Architectures` |
| Right tool for the job | dbt-on-Athena for SQL transforms; container Lambda (SARIMA) for ML; static S3 site for BI (QuickSight gated) | n/a |

**Risks:** None High. The transform core (full-CTAS) is the forward-looking efficiency smell shared
with Reliability §3; negligible at 1.38 M rows / current scale.

## 5. Cost Optimization

**Adopt consumption model, measure efficiency, stop spending on undifferentiated heavy lifting,
analyze & attribute expenditure.**

| Practice | Evidence | Re-verify |
|---|---|---|
| Consumption / scale-to-zero | Everything serverless; no provisioned compute; QuickSight Enterprise declined (Standard) | n/a |
| Spend guardrails | Athena 10 GB per-query cap; `bi_disabled` excludes 4 marts from the default build; reserved concurrency caps runaway invokes | `dbt ls --exclude tag:bi_disabled` |
| Storage tiering | `processed/` → Intelligent-Tiering day 0; `athena-results/` expire 7 d; `raw/stream/` 60 d; noncurrent 7 d | `aws s3api get-bucket-lifecycle-configuration` |
| Reactive cost alarm | CloudWatch `EstimatedCharges > $8` (us-east-1) → billing SNS email | `aws cloudwatch describe-alarms --alarm-names openaq-billing` |
| **Proactive cost budget** | **AWS Budget `…-monthly`** (this review): monthly COST budget at the envelope ceiling, email at 80 % **forecasted** + 100 % **actual** — the proactive signal the alarm lacks (`terraform/monitoring.tf`) | `aws budgets describe-budgets --account-id 703668403514` |
| Cost attribution | consistent `Project`/`ManagedBy` tags enable Cost Explorer grouping | Cost Explorer |

**Risks:** None High. Full-CTAS daily rebuild is ~cents/mo at current scale (verified low, not a real
cost line).

## 6. Sustainability

**Maximize utilization, adopt efficient hardware/software, reduce downstream impact, right-size.**

| Practice | Evidence |
|---|---|
| Energy-efficient hardware | **arm64 / Graviton** on all Lambdas (better perf/watt than x86) |
| No idle capacity | Scale-to-zero serverless throughout; no always-on instances; Kinesis ON_DEMAND |
| Minimize data movement & scans | Partition projection + Parquet/snappy + 10 GB scan cap → less data scanned per query; GZIP on raw stream; Intelligent-Tiering moves cold data to lower-energy storage classes |
| Right-sized retention | Tiered lifecycle expiry (results 7 d, stream 60 d) avoids storing data with no consumer |

**Risk (deferred):** full-refresh recomputes the whole history daily — incremental processing would
cut compute/scan (and thus energy) once history grows; same trigger as the Reliability/Performance
deferral. ADR-logged.

---

## Risk register (Well-Architected HRIs)

| # | Pillar | Risk | Severity | Disposition |
|---|---|---|---|---|
| R1 | Reliability | DLQs inert on synchronous scheduled paths | Medium | Accepted — direct Errors + freshness alarms cover it |
| R2 | Rel/Perf/Sustain | Full-CTAS daily rebuild won't scale past ~5–10× history | Medium | Deferred (ADR) — incremental when history > 1–2 yr |
| R3 | Security | No WAF on public API | Medium | **Accepted DECLINE** — out of $-envelope; throttle+concurrency cap blast radius |
| R4 | Security | No dedicated CloudTrail trail | Low | **Accepted** — 90-day default Event history at $0 suffices for a demo |
| R5 | Security | Broad Glue *read* on CI role | Low | Accepted — writes scoped; gated behind prior compromise |

No **High** risks remain open. R3/R4 are explicit, envelope-justified declines (documented, not
oversights) — the same "accepted-risk ADR" pattern the framework expects.

## What this review changed (reproducibly)

- **Added the missing canonical Cost control:** an `aws_budgets_budget` in `terraform/monitoring.tf`
  (var `monthly_budget_usd`, default 8). Previously the project had only a *reactive* `EstimatedCharges`
  alarm; the budget adds a *proactive forecasted* signal. Free (first two budgets). Deploy: `terraform
  apply`; verify `aws budgets describe-budgets --account-id 703668403514`.
- Everything else above was already implemented and live-verified — this doc grounds it in the
  framework and records the accepted-risk declines explicitly.

## How to re-run this review

1. Live inventory: re-probe per `DEPLOYED-SPECS-AND-AUDIT.md` (the canonical resource list).
2. Per-pillar: run the **Re-verify** command in each table against `ap-southeast-1` / account
   `703668403514` and confirm the cited config still holds (live-state HARD GATE).
3. Re-score with the adversarial-verify workflow in `RESEARCH-WORKFLOW.md` if the architecture
   materially changes. Update `ARCHITECTURE-EVALUATION.md` (scores) and this file (pillar mapping)
   together.

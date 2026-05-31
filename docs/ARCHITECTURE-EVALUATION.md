# Architecture Evaluation — Vietnam Air Quality Pipeline

> Method: kit's multi-lens + adversarial-verify workflow (RIPER-5). 8 expert lenses scored the
> architecture independently (37 agents), then every high/medium finding was handed to a **skeptic
> agent prompted to refute it** against the real code. Only verdicts below are post-verification —
> severities are the *adjusted* ones, not the initial claims. Generated 2026-05-30.
> Companions: PIPELINE-REPORT.md, DATA-LIFECYCLE.md, DEPLOYED-SPECS-AND-AUDIT.md.
> Next dev cycle: triage open items via `docs/RESEARCH-WORKFLOW.md` (live-state HARD GATE) and the
> context router `process/context/all-context.md`; Resolution status (bottom) is live as of 2026-05-31.

## Scorecard (1–5)

| Lens | Score | One-line verdict |
|---|---|---|
| Reproducibility | **3** → now stronger | Pinned providers, single-sourced roster, real CI — but from-zero deploy needs manual zip-build + codebuild-source upload, and local-only state. *(Resolved 2026-05-30: Lambda `source_code_hash` + codebuild-source now built/uploaded by Terraform; only local state remains — see Resolution status.)* |
| Reliability | **3** | Good app-layer retry/idempotency; orchestration-layer failure capture is weaker than docs imply (DLQs largely inert on the synchronous scheduled paths). |
| Security | **3** | Encryption solid, runtime role least-privilege, secret hardened; residual: unauthenticated API with no throttle, over-broad CI Glue role, local unencrypted state. |
| Cost | **3** | Correct guardrails (10GB cap, projection, bi_disabled). Full-CTAS daily rebuild is an architectural smell but negligible $ at 1.38M rows today. |
| Scalability | **3** | Edges scale; the transform core (full-refresh over unbounded history) is the break point at ~5–10× history. |
| Data Quality | **4** | Genuinely strong: parameter-aware filters, correct EPA-2024 AQI, circular wind mean, grain tests. Gaps are value-range tests + dead `corrected_pm25`. |
| Observability | **3** → now stronger | Credible skeleton (X-Ray, 4 alarms, completeness monitor) with a structural blind spot: the monitor self-suppresses on the exact "silently dead" case. *(Resolved 2026-05-30: now 14 alarms + the silent-death `DaysSinceLastNewMart` signal — see Resolution status.)* |
| Maintainability | **4** | 85 passing tests across 6 handlers, real PR-gating CI, deduped roster, clean DRY. Gaps are deploy plumbing (no source_code_hash, manual zip). |

**Overall ≈ 3.3 / 5 — strong portfolio-grade engineering; a few real production-hardening gaps.**

## What adversarial verification changed

Of 15 material findings put to a skeptic: **1 upheld high · 8 confirmed but downgraded to medium/low · 4 partially refuted · 2 effectively refuted.** This is the value of the iteration — it removed inflated claims and kept the real ones.

| Finding | Lens | Claimed | **Verified** | Verdict note |
|---|---|---|---|---|
| batch_sync swallows per-station failures (no metric/alarm/retry) | Reliability | high | **HIGH** | Confirmed; persistent station failure is silent, undetected data loss. The one finding that survived at high. |
| stale-suppression masks a fully dead pipeline | Observability | high | **high*** | Monitor suppresses SNS once data_age>7d — exactly the silent-death case. (*lens-level, not separately re-verified) |
| no Lambda Errors/Throttle alarms; no DLQ-depth alarm | Observability | high | **high*** | Confirmed in lens evidence; only indirect/lagging proxies exist. |
| mart-expiry: marts under `athena-results/` 7-day rule | Reliability | high | **medium** | Confirmed mechanism, but source data survives → downtime not permanent loss; this is the regression from my own `enforce=true` change. |
| DLQs never fire on synchronous scheduled invocations | Reliability | high | **medium** | Confirmed; DLQs are dead paths for the hot paths, but 30-min cadence + indirect alarms soften it. |
| no README / ordered runbook | Reproducibility | high | **medium** | Partially refuted — `docs/workshop/5.1–5.6` IS an ordered runbook; real gap is no root entry + 2 missing zip-build steps. |
| codebuild-source.zip built/uploaded by hand | Reproducibility | high | **medium** | Confirmed; dbt layer not reproducible from `terraform apply` alone. |
| Lambda has no `source_code_hash` | Repro/Maint | medium | **medium** | Confirmed; rebuilt zips silently not redeployed — contradicts build.sh comment. |
| secret bootstrap: required `openaq_api_key` var is unused | Reproducibility | medium | **medium** | Confirmed; tfvars comment is affirmatively false; key must be set twice. |
| weather_ingest no DLQ/alarm; all-stations outage returns success | Reliability | medium | **medium** | Confirmed; silently degrades weather/forecast marts. |
| public API no throttle/WAF/reserved-concurrency | Security | medium | **medium** | Confirmed; impact is availability + shared-Lambda blast radius more than runaway $ (10GB cap + tiny mart). |
| local state, no remote backend | Reproducibility | high | **medium** | Confirmed but state is gitignored (good hygiene); gap is no shared/locked backend. |
| CI dbt_runner role: account-wide Glue delete | Security | medium | **low** | Confirmed over-broad, but exploitation gated behind prior in-account compromise; audit schema name IS static so it can be scoped. |
| tfstate "historically held the plaintext key" | Security | medium | **low** | **Refuted** — both state files only ever held `REPLACE_ME`; real key injected as a separate SM version. Local-unencrypted-state hygiene gap remains. |
| dbt test failures non-blocking & "silent" | Reliability | medium | **low** | Partially refuted — `dbt run` failure DOES fail the build; completeness monitor gives a station signal. Real gap: test suite has no alarm. |
| full-CTAS daily rebuild / staging view over CSV.GZ | Cost | medium ×2 | **low ×2** | Confirmed mechanism, but ~cents/month at current scale; forward-looking smell, not a current cost line. |

## Design-decision register (ADR-style, post-review)

**Sound (keep):** seed-as-single-source-of-truth roster via `csvdecode`; partition projection; 10GB scan cap + enforced workgroup; arm64 + GZIP + tiered expiry; pinned provider + AWS CodeBuild image (GHCR rate-limit pivot); forecast `count` gate; full-refresh table marts at *this* scale; circular-mean wind; pm25-only 500 ceiling; INNER-JOIN allowlist; `conftest` module-collision shim; secret-out-of-state via `ignore_changes` + post-deploy injection.

**Questionable (revisit as it grows):** flat Terraform root with ~~local state~~ (✅ 2026-05-31: moved to versioned/SSE-S3 remote backend with native `use_lockfile` — **no DynamoDB**, which the original suggestion over-specified for a single operator); **out-of-band artifact packaging** (→ `archive_file` + `aws_s3_object` + `source_code_hash`); **Kinesis ON_DEMAND** for ~KB/hour (→ 1 provisioned shard, or drop Kinesis→direct S3 PutObject); **full-CTAS** (→ incremental once history >1–2 yr); **completeness stale-suppression** conflating upstream-lag with pipeline-death.

**Risky (address):** **batch_sync returns success on per-station failure** (→ emit `BatchStationFailures` metric + alarm, or raise over threshold); **proxy-only alarming** with no direct Lambda Errors/DLQ-depth alarms; **dual secret-bootstrap paths** (pick one).

## Recommended next actions, ranked by verified severity

1. **(HIGH) Make batch failures observable** — emit a CloudWatch metric on the `failed` station list and alarm on it; same for `weather_ingest` all-stations-failed. Today these rot silently.
2. **(HIGH) Add direct alarms** — Lambda `Errors`/`Throttles` (at least aqi_api + streaming), DLQ `ApproximateNumberOfMessagesVisible>0`, and a **mart-freshness alarm** (`DaysSinceLastNewMart`) that fires when `MAX(measurement_date)` stops advancing — the true silent-death signal the current monitor suppresses. (`completeness_check` already computes `data_age_days`; it's one `put_metric_data` call away.)
3. **(MEDIUM) Fix the mart-expiry regression** — point the workgroup result location at `athena-results/query/` so dbt marts under `processed/` are not on the 7-day delete rule (the `enforce=true` change introduced this).
4. **(MEDIUM) Close reproducibility gaps** — add `source_code_hash`; bring `codebuild-source.zip` into Terraform (`archive_file`+`aws_s3_object`) or a scripted step; add a root README linking the workshop and folding in the two missing zip-build steps; resolve the dual secret-bootstrap path.
5. **(MEDIUM) API hardening** — `default_route_settings` throttle + `reserved_concurrent_executions` on aqi_api. **(✅ DONE & live — see Resolution status.)**
6. **(LOW, scope-down) Tighten the CI dbt_runner role** to `database/openaq_mart*` + `table/openaq_mart*/*` (audit schema name is static) **(✅ DONE & live)**; move state to an encrypted S3 backend **(⏳ still open)**.

## Resolution status (updated 2026-05-30, verified live)

The HIGH/MEDIUM findings above were acted on the same day; this block is the current truth (the
scorecard and verdict table are preserved as the point-in-time evaluation).

- ✅ **batch_sync silent per-station failure** → `BatchStationFailures` metric + `openaq-batch-station-failures` alarm shipped. **It immediately earned its keep:** the first live run surfaced `BatchStationFailures=5` — all 5 *active* stations failing PutObject (streaming a non-seekable `StreamingBody`: `MissingContentLength`, then `SignatureDoesNotMatch`), so new batch data had been silently not syncing (this is why the mart was stuck at 2026-05-20). Fixed `_copy_object` to read the object into bytes; redeployed and re-verified live: `success=63 failed=0 copied=34`.
- ✅ **No direct Lambda Errors / DLQ-depth alarms** → per-function `Errors` ×5, `aqi_api` Throttles, both DLQ-depth alarms shipped (14 openaq alarms live).
- ✅ **Stale-suppression masks dead pipeline** → `DaysSinceLastNewMart` metric (NOT suppressed) + `openaq-mart-stale` alarm (>21d) shipped; verified emitting (=10).
- ✅ **weather_ingest no alarm / all-stations outage silent** → `WeatherIngestErrors` metric + `openaq-weather-ingest-errors` alarm shipped; verified emitting (=0).
- ✅ **mart-expiry under `athena-results/` 7-day rule** → `enforce_workgroup_configuration=false`; dbt marts now write to `processed/openaq_mart/` (Intelligent-Tiering, off the expiry path). The action #3 mechanism above ("repoint to `athena-results/query/`") was proven infeasible — under enforcement Athena rejects CTAS `external_location` and marts would still nest under the expired prefix. Verified live; see DATA-LIFECYCLE.md §6.
- ✅ **No `source_code_hash`** → added to all 5 Lambda functions; rebuilt zips now redeploy (proven this round).
- ✅ **codebuild-source.zip built/uploaded by hand** → now packaged + uploaded by Terraform (`archive_file` + `aws_s3_object`, pure-Go so no local `zip` needed); buildspec moved to the zip root. The dbt transform layer is now reproducible from `terraform apply` alone. Verified live: a fresh dbt build consumed the Terraform-built zip and succeeded.
- ✅ **Dual secret-bootstrap path** → removed the unused `openaq_api_key` variable + its dead `terraform.tfvars` copy; Secrets Manager (post-deploy `postdeploy.sh` injection) is now the single path. `terraform plan` showed zero infra diff, confirming it was dead config.
- ✅ **API hardening (rec #5)** → DONE & live (verified 2026-05-31): `$default` stage throttle
  `burst=20 / rate=10` + `reserved_concurrent_executions=10` on `aqi_api`.
- ✅ **CI dbt_runner Glue scope-down (rec #6)** → DONE & live: role `openaq_dbt_runner_role` scoped to
  `database/openaq_mart*`, `table/openaq_mart*/*`, `openaq_raw`, `default` — no account-wide wildcard.
- ✅ **Local Terraform state → encrypted remote backend** → DONE & verified live 2026-05-31: state moved
  to versioned/SSE-S3 bucket `openaq-tfstate-thanhtrung102` with native `use_lockfile` (NO DynamoDB —
  out-of-envelope for a single operator); `terraform plan` clean no-op over 88 resources. Closed the
  single-laptop durability SPOF (workstation was not backed up out-of-band).
- ⏳ **Still genuinely open (verified 2026-05-31):** public API has **no WAF** — and this is a deliberate
  **DECLINE**: throttle (burst 20/rate 10) + reserved-concurrency (10) already cap the availability/cost
  blast radius, and WAFv2's ~$5+/mo floor exceeds the whole ~$3–8/mo envelope for a read-only public-data
  GET. Recorded as accepted residual risk, not an open gap.

## Process note
The verification step refuted/softened more than half the initial findings — including two I'd previously have reported with confidence (the "no runbook" and "tfstate held the secret" claims). Treat any single-pass review of this codebase with that prior: it presents worse than it is on first read, because the workshop docs and the secret-migration design aren't obvious without checking the artifacts.

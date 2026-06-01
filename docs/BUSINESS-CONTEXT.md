# Business Context & Project Proposal — Vietnam Air Quality Pipeline

> Derived 2026-06-01 from **owner input** (5 framing answers) cross-checked against verified artifacts.
> This is the **canonical owner of business / proposal framing** — the counterpart to the technical
> docs. It is the *proposal* half of the AWS **First Cloud Journey (FCJ)** deliverable; the *workshop*
> half is `docs/workshop/5.1–5.6`. Reference report format:
> https://danielleit241.github.io/aws-fcj-report/ (workshop + proposal sections).
> Nothing here is a deployed-state claim; for live facts see `docs/DEPLOYED-SPECS-AND-AUDIT.md`.

---

## 0. The honest frame (read this first)

This is an **AWS architecture portfolio / demo project** built for the **First Cloud Journey (FCJ)**
program (AWS Vietnam community / FPT University learning track). It is **not** a funded public service,
**not** a production system with real users, and has **no regulatory or policy consumer**.

That makes the "business problem" **dual**:

- **Primary (the real objective):** demonstrate end-to-end **serverless AWS data-engineering
  competency** for portfolio/FCJ review.
- **Narrative (the vehicle):** a **Vietnam PM2.5 air-quality analytics** use case, chosen because it is
  data-rich, locally relevant, and exercises ingestion + transform + ML + serving + governance.

Everything domain-facing (AQI, WHO/QCVN exceedance, health analogies) is a **demonstration of capability
on a realistic dataset**, not a service offered to an audience.

---

## 1. Demonstration objective (the actual success criteria)

Because this is a portfolio demo, success = **showing mastery**, not adoption or revenue. The pipeline is
designed to evidence each of these, and the repo proves them live:

| Competency demonstrated | Evidence in the system |
|---|---|
| Serverless / scale-to-zero, cost-disciplined | ~$3.22/mo, no persistent compute (`5.1`, billing alarm) |
| Reproducible IaC | Terraform, remote S3 state + native lock (`infra-terraform`) |
| Multi-source ingestion | batch + streaming + weather Lambdas (`DATA-LIFECYCLE §1`) |
| Catalog/query without ops | Glue partition projection + Athena (`infra-terraform`) |
| Declarative transform with correct domain science | dbt-on-Athena; EPA-2024 AQI, WHO/QCVN (`domain-data-quality`) |
| Least-privilege + secret hygiene | per-function IAM, Secrets Manager, no plaintext key (`PIPELINE-REPORT §4`) |
| Observability | X-Ray, 14 CloudWatch alarms, completeness monitor (`ARCHITECTURE-EVALUATION`) |
| ML forecast | SARIMA-in-Lambda 7-day forecast — `count`-gated but **deployed & live since 2026-06-01** (`DATA-LIFECYCLE §4`) |
| Public serving | API Gateway + GeoJSON + Leaflet map (`serving-api-dashboard`) |

These are the **demo-appropriate KPIs** — see §5.

---

## 2. Narrative problem (the use-case vehicle)

*Illustrative framing only — no real user or regulator consumes this.*

Vietnam, and Hanoi in particular, carries a heavy PM2.5 burden; air-quality information is fragmented and
hard to relate to either **health risk** or **air-quality standards**. The demo shows how a cheap
serverless pipeline could make PM2.5 data understandable as (a) an **AQI/health signal** for the public
and (b) a **WHO 2021 / Vietnam QCVN 05:2023 exceedance** view — plus a short-term forecast. The four
analysis surfaces (QuickSight sheets, gated) encode this narrative: Executive Health Scorecard, Seasonal
& Weather Drivers, Compliance & Target Trajectory, Forecast Monitor.

## 3. Audience

- **Primary (real):** FCJ reviewers / AWS mentors / portfolio viewers assessing cloud-architecture and
  data-engineering skill.
- **Secondary (narrative personas — illustrative, not real users):** residents (AQI map), analysts
  (weather-driver views), a notional "compliance" viewer (exceedance stats). These shape the *features*,
  but no such audience is served in production.

## 4. Scope & ambition (deliberately bounded)

- **Geographic:** **21 Vietnam stations** (17 Hanoi-area, 4 Ho Chi Minh City). No national-scale or
  expansion goal — VN stations is the intended bound.
- **No regulatory/policy obligations.** WHO/QCVN exceedance is demonstrative analytics, not a compliance
  product.
- **Single operator**, demo lifecycle, ~$3–8/mo envelope (see `all-context.md` Constraint Envelope).

## 5. Success metrics (demo-appropriate — promoted from operational SLAs)

| Metric | Target | Why it counts for a demo |
|---|---|---|
| End-to-end correctness | proven live (live probes pass) | shows the architecture actually works |
| Monthly cost | within ~$3–8/mo envelope | proves cost discipline |
| Reproducibility | stack stands up from `terraform apply` | proves IaC maturity |
| Mart freshness | within OpenAQ archive lag (~3–10 d) | proves the pipeline advances |
| Forecast RMSE (if forecast enabled) | < 25 µg/m³ (alarm threshold) | proves the ML path is monitored |

Adoption/usage metrics are intentionally **not** tracked — there is no audience to measure.

## 6. Non-goals (explicit)

- ❌ A funded or SLA-backed public service.
- ❌ A regulatory / compliance system (no policy consumer — owner-confirmed).
- ❌ Real-time or sub-daily reporting (daily grain by design).
- ❌ Multi-tenant or national-scale ingestion.
- ❌ Validated low-cost-sensor health correction (`corrected_pm25` is an unvalidated heuristic — see
  `domain-data-quality`).

## 7. Relationship to the FCJ deliverable format

| FCJ section | This repo |
|---|---|
| **Workshop** (bilingual build-from-scratch) | `docs/workshop/5.1–5.6` |
| **Proposal / business framing** | **this document** |
| Reference report shape | https://danielleit241.github.io/aws-fcj-report/ |

## 8. Provenance

- **Owner input, 2026-06-01:** (1) AWS architecture portfolio demo, FCJ; (2) workshop/portfolio;
  (3) demo project; (4) scope = VN stations; (5) no regulatory policies.
- **Verified artifacts:** marts (`DATA-LIFECYCLE §3`), encoded standards (`domain-data-quality`),
  constraint envelope + identity (`all-context.md`), QuickSight sheets (`workshop/5.1`).
- All live deployed-state assertions remain owned by `docs/DEPLOYED-SPECS-AND-AUDIT.md` and were
  re-verified live 2026-05-31 / 2026-06-01.

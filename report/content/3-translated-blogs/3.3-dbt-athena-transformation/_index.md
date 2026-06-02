+++
title = "Blog 3"
weight = 3
chapter = false
pre = " <b> 3.3. </b> "
+++

# How BMW Group built a serverless terabyte-scale data transformation architecture with dbt and Amazon Athena

_By Philipp Karg, Cizer Pereira, and Selman Ay — 29 April 2025, AWS Big Data Blog
([Amazon Athena](https://aws.amazon.com/blogs/big-data/category/analytics/amazon-athena/),
Amazon QuickSight, Analytics, Customer Solutions)._

## Summary

BMW Group runs a large analytics platform on a fully **serverless** transformation stack: **dbt** for
the modelling and testing logic, and **Amazon Athena** as the query engine. Because Athena scales
automatically and bills only for data scanned, the team manages no clusters and pays for compute only
when transformations actually run.

Key points from the post:

- **Layered models:** roughly **400 dbt models** are organised into three stages — **Source** (raw),
  **Prepared** (cleansed/standardised), and **Semantic** (business-ready aggregates) — making the
  pipeline modular and easy to reason about.
- **Incremental processing:** models process only new or changed data instead of rebuilding entire
  datasets, which sharply reduces both processing volume and Athena scan cost.
- **Workgroup isolation:** separate **Athena workgroups** isolate transformation, testing, BI, and
  ad-hoc query patterns, giving per-workgroup cost allocation and governance.
- **CI/CD:** **GitHub Actions** deploy changes from pull requests; schema evolution is handled through
  dbt configuration rather than hand-written DDL.
- **Built-in data quality:** dbt **tests** validate schema constraints, referential integrity, and
  custom business rules automatically on every pull request and on nightly builds.
- **Cost trade-off:** materialising semantic **tables** (instead of recomputing complex views) removed
  redundant computation and produced a net cost reduction despite more dbt work overall.

## Applied in this project

The Vietnam Air Quality pipeline is the same architecture at internship scale. It runs
**dbt-athena-community** against the `openaq_workgroup` (with a **10 GB per-query scan cap**) and
organises **17 models** into the same kind of layers BMW uses: **staging → intermediate → marts**
(mapping to Source → Prepared → Semantic). The default build is **13 of 17** marts
(`--exclude tag:bi_disabled`), and the suite carries **84 tests** — generic, singular freshness and
invariant checks, two **unit tests** for the EPA-2024 AQI breakpoint maths, and dbt-expectations range
checks. The one substitution: instead of GitHub Actions, an **AWS CodeBuild** project
(`openaq-dbt-runner`) runs dbt on a daily schedule, re-packaged on each `terraform apply`. Marts are
materialised tables read by the `aqi_api` Lambda — the same "materialise the semantic layer" choice the
post recommends for cost.

**Source:** [How BMW Group built a serverless terabyte-scale data transformation architecture with dbt and Amazon Athena](https://aws.amazon.com/blogs/big-data/how-bmw-group-built-a-serverless-terabyte-scale-data-transformation-architecture-with-dbt-and-amazon-athena/).

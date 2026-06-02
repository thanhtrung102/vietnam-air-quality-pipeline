+++
title = "Blog 3"
weight = 3
chapter = false
pre = " <b> 3.3. </b> "
+++

# How BMW Group built a serverless terabyte-scale data transformation architecture with dbt and Amazon Athena

_Summarised in English from the AWS Big Data Blog post by Philipp Karg, Cizer Pereira, and Selman Ay —
29 April 2025
([Amazon Athena](https://aws.amazon.com/blogs/big-data/category/analytics/amazon-athena/),
Amazon QuickSight, Analytics, Customer Solutions). Original article linked at the bottom; the write-up
below is in my own words._

## The setup

BMW Group runs a large analytics platform on a fully **serverless** transformation stack: **dbt**
provides the modelling and testing logic, and **Amazon Athena** is the query engine that executes the
SQL. Because Athena scales on demand and bills only for the data each query scans, the team operates no
clusters and pays for transformation compute only while it actually runs.

## Why dbt on Athena

Pairing dbt with Athena lets engineers express transformations as version-controlled SQL models while
the platform handles execution and scaling. Athena's efficiency on large Parquet datasets, combined
with its serverless billing, means the team can focus on writing good transformations rather than
sizing and babysitting infrastructure.

## A layered model architecture

The post describes roughly **400 dbt models** organised into three stages:

- **Source** — raw data as ingested.
- **Prepared** — cleansed and standardised tables.
- **Semantic** — business-ready aggregates consumed by analytics and BI.

This layering keeps each transformation small and composable, and makes lineage easy to follow from raw
input to business output.

## Incremental processing

Rather than rebuilding entire datasets on every run, the dbt models process **only new or changed
data** incrementally. That sharply reduces both the volume of data processed and the Athena scan cost,
which is what makes the approach affordable at terabyte scale.

## Workgroup isolation

Different query patterns — transformations, testing, BI/visualization, and ad-hoc analysis — are run in
**separate Athena workgroups**. Isolating them gives per-workgroup cost allocation and governance, so
each workload's spend and configuration can be managed independently.

## CI/CD and data quality

Deployments are automated through **GitHub Actions**, triggered from pull requests, with schema changes
managed through dbt configuration rather than hand-written DDL. dbt's built-in **tests** validate schema
constraints, referential integrity, and custom business rules automatically on every pull request and
on nightly builds — so data-quality regressions are caught before they reach consumers.

## The cost trade-off

A notable lesson: moving from complex, repeatedly-recomputed **views** to **materialised** semantic
tables removed redundant computation and produced a net cost reduction, even though it increased the
total amount of dbt work. Materialising the semantic layer trades a little extra build cost for much
cheaper, faster reads downstream.

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

# Vietnam Air Quality Pipeline

## Problem Statement

Air quality across Vietnamese cities has been deteriorating, yet long-term trends and seasonal patterns remain poorly understood by the public and policymakers. This project addresses the analytical question: how has air quality in major Vietnamese cities changed over the past three years, and which pollutants (PM2.5, PM10, NO₂, O₃, CO) and seasons pose the greatest health risk to residents? By combining historical measurements with near-real-time readings, the pipeline enables both retrospective trend analysis and timely awareness of hazardous episodes.

The pipeline ingests historical and streaming air quality data from the OpenAQ API into Amazon S3, catalogs it via AWS Glue, and makes it queryable through Amazon Athena. Transformation and aggregation layers are built with dbt (dbt-athena-community), while orchestration is managed through Kestra flows. Infrastructure is provisioned as code with Terraform, and a lightweight dashboard surfaces city-level AQI trends, pollutant breakdowns, and seasonal heatmaps for end users.

## Architecture

![Architecture](docs/architecture.png)

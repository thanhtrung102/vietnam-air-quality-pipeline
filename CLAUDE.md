# Vietnam Air Quality Pipeline — Project Context

## AWS Configuration
- **Region:** ap-southeast-1
- **S3 bucket name:** openaq-pipeline-tt *(fill in after Terraform apply)*
- **Athena workgroup:** openaq_workgroup
- **Glue database:** openaq_raw
- **Kinesis stream name:** openaq_stream

## S3 Prefixes
- **Historical batch:** `raw/batch/locationid={id}/year={year}/month={month}/`
- **Streaming:** `raw/stream/{year}/{month}/{day}/{hour}/`
- **Processed mart:** `processed/mart_daily_air_quality/`

## dbt
- **Project name:** openaq_transform
- **Adapter:** dbt-athena-community
- **Mart table partitions on:** measurement_date
- **Mart table clusters on:** parameter, location_id

## Naming Conventions
- All identifiers: snake_case
- All AWS resources prefixed with: `openaq_`

## OpenAQ
- **Public archive bucket:** openaq-data-archive (us-east-1)
- **Vietnamese station IDs:** to be filled after archive exploration

## IAM
- **Local dev user:** terraform-admin (pre-existing, not managed by Terraform)

## Rules
- **Never hardcode API keys** — always read from environment variables

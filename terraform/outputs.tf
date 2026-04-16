# ── Region ────────────────────────────────────────────────────────────────────

output "aws_region" {
  description = "AWS region where all resources are deployed"
  value       = var.aws_region
}

# ── S3 ────────────────────────────────────────────────────────────────────────

output "s3_bucket_name" {
  description = "Name of the project S3 bucket"
  value       = aws_s3_bucket.main.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the project S3 bucket"
  value       = aws_s3_bucket.main.arn
}

# ── Glue ──────────────────────────────────────────────────────────────────────

output "glue_database_name" {
  description = "Name of the Glue Data Catalog database"
  value       = aws_glue_catalog_database.openaq_raw.name
}

# ── Athena ────────────────────────────────────────────────────────────────────

output "athena_workgroup_name" {
  description = "Name of the Athena workgroup"
  value       = aws_athena_workgroup.openaq.name
}

# ── Kinesis ───────────────────────────────────────────────────────────────────

output "kinesis_stream_name" {
  description = "Name of the Kinesis Data Stream"
  value       = aws_kinesis_stream.openaq.name
}

output "kinesis_stream_arn" {
  description = "ARN of the Kinesis Data Stream"
  value       = aws_kinesis_stream.openaq.arn
}

output "kinesis_firehose_arn" {
  description = "ARN of the Kinesis Firehose delivery stream"
  value       = aws_kinesis_firehose_delivery_stream.openaq.arn
}

# ── IAM ───────────────────────────────────────────────────────────────────────

output "pipeline_role_arn" {
  description = "ARN of the openaq_pipeline_role IAM role (assumed by EC2/Lambda at runtime)"
  value       = aws_iam_role.pipeline.arn
}

output "firehose_role_arn" {
  description = "ARN of the openaq_firehose_role IAM role (assumed by Kinesis Firehose)"
  value       = aws_iam_role.firehose.arn
}

# ── AQI API ───────────────────────────────────────────────────────────────────

output "aqi_api_url" {
  description = "HTTP API Gateway URL for the AQI GeoJSON API (consumed by Leaflet map)"
  value       = aws_apigatewayv2_stage.aqi_api.invoke_url
}

# ── IoT Lens Gap Fixes ────────────────────────────────────────────────────────

output "streaming_dlq_url" {
  description = "SQS DLQ URL for streaming Lambda failures (Gap 1)"
  value       = aws_sqs_queue.streaming_dlq.url
}

output "streaming_dlq_arn" {
  description = "SQS DLQ ARN for streaming Lambda failures (Gap 1)"
  value       = aws_sqs_queue.streaming_dlq.arn
}

output "openaq_api_key_secret_arn" {
  description = "Secrets Manager ARN for the OpenAQ API key (Gap 2). Inject real value post-deploy."
  value       = aws_secretsmanager_secret.openaq_api_key.arn
}

output "openaq_api_key_secret_name" {
  description = "Secrets Manager secret name for the OpenAQ API key (Gap 2)"
  value       = aws_secretsmanager_secret.openaq_api_key.name
}

# ── QuickSight (Phase 2) ──────────────────────────────────────────────────────

output "quicksight_data_source_arn" {
  description = "ARN of the QuickSight Athena data source (shared by all SPICE datasets)"
  value       = aws_quicksight_data_source.athena.arn
}

output "quicksight_dataset_ids" {
  description = "Map of dataset name → dataset_id for all nine SPICE datasets"
  value = {
    daily_aqi            = aws_quicksight_data_set.daily_aqi.data_set_id
    health_summary       = aws_quicksight_data_set.health_summary.data_set_id
    annual_monthly_trend = aws_quicksight_data_set.annual_monthly_trend.data_set_id
    monthly_profile      = aws_quicksight_data_set.monthly_profile.data_set_id
    diurnal_profile      = aws_quicksight_data_set.diurnal_profile.data_set_id
    aq_weather_daily     = aws_quicksight_data_set.aq_weather_daily.data_set_id
    exceedance_stats     = aws_quicksight_data_set.exceedance_stats.data_set_id
    pollutant_ratio      = aws_quicksight_data_set.pollutant_ratio.data_set_id
    forecast_accuracy    = aws_quicksight_data_set.forecast_accuracy.data_set_id
  }
}

output "quicksight_dataset_arns" {
  description = "Map of dataset name → ARN (used in aws_quicksight_analysis data_set_identifiers)"
  value = {
    daily_aqi            = aws_quicksight_data_set.daily_aqi.arn
    health_summary       = aws_quicksight_data_set.health_summary.arn
    annual_monthly_trend = aws_quicksight_data_set.annual_monthly_trend.arn
    monthly_profile      = aws_quicksight_data_set.monthly_profile.arn
    diurnal_profile      = aws_quicksight_data_set.diurnal_profile.arn
    aq_weather_daily     = aws_quicksight_data_set.aq_weather_daily.arn
    exceedance_stats     = aws_quicksight_data_set.exceedance_stats.arn
    pollutant_ratio      = aws_quicksight_data_set.pollutant_ratio.arn
    forecast_accuracy    = aws_quicksight_data_set.forecast_accuracy.arn
  }
}

output "quicksight_service_role_arn" {
  description = "ARN of the QuickSight service role (grant this in the QuickSight console under Security & Permissions)"
  value       = aws_iam_role.quicksight_service.arn
}

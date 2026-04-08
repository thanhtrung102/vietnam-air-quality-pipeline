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

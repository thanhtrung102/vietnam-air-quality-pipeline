variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "ap-southeast-1"
}

variable "project_name" {
  description = "Project name prefix used for resource naming"
  type        = string
  default     = "openaq-pipeline"
}

variable "s3_bucket_suffix" {
  description = "Suffix appended to the S3 bucket name (e.g. your initials). Bucket name = openaq-pipeline-{suffix}"
  type        = string
}

variable "alert_email" {
  description = "Email address to receive CloudWatch alarm notifications via SNS"
  type        = string
}

variable "openaq_api_key" {
  description = "OpenAQ v3 API key for the streaming Lambda function"
  type        = string
  sensitive   = true
}

variable "lambda_batch_zip_path" {
  description = "Path to the batch sync Lambda zip file, relative to the terraform/ directory"
  type        = string
  default     = "../lambda/batch_sync.zip"
}

variable "lambda_streaming_zip_path" {
  description = "Path to the streaming producer Lambda zip file, relative to the terraform/ directory"
  type        = string
  default     = "../lambda/streaming.zip"
}

variable "lambda_aqi_api_zip_path" {
  description = "Path to the AQI API Lambda zip file, relative to the terraform/ directory"
  type        = string
  default     = "../lambda/aqi_api.zip"
}

variable "lambda_completeness_zip_path" {
  description = "Path to the completeness check Lambda zip file, relative to the terraform/ directory"
  type        = string
  default     = "../lambda/completeness_check.zip"
}

variable "lambda_weather_zip_path" {
  description = "Path to the weather ingest Lambda zip file, relative to the terraform/ directory"
  type        = string
  default     = "../lambda/weather_ingest.zip"
}

variable "quicksight_admin_email" {
  description = "Email address to register as a QuickSight Author (must match an IAM user's email or be a valid address for QuickSight managed users)"
  type        = string
}

variable "forecast_lambda_image_uri" {
  description = <<-EOT
    ECR image URI for the forecast_generate container Lambda.
    Set to a non-empty value only after the Docker image has been built and pushed to ECR.
    Example: 123456789012.dkr.ecr.ap-southeast-1.amazonaws.com/openaq-forecast-generate:latest

    Deployment steps:
      1. terraform apply                  → creates ECR repo (Lambda skipped while this is empty)
      2. docker build lambda/forecast_generate/
      3. docker tag + docker push to ECR
      4. terraform apply -var="forecast_lambda_image_uri=<URI>:latest"
  EOT
  type        = string
  default     = ""
}

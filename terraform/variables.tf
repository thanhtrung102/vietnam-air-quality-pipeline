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

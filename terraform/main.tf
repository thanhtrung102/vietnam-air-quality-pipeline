terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ── Locals ────────────────────────────────────────────────────────────────────

locals {
  bucket_name = "${var.project_name}-${var.s3_bucket_suffix}"

  common_tags = {
    Project   = var.project_name
    ManagedBy = "terraform"
  }
}

# ── S3 Bucket ─────────────────────────────────────────────────────────────────

resource "aws_s3_bucket" "main" {
  bucket = local.bucket_name
  tags   = local.common_tags
}

resource "aws_s3_bucket_versioning" "main" {
  bucket = aws_s3_bucket.main.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "main" {
  bucket = aws_s3_bucket.main.id

  # ACL-based public access is blocked — we use bucket policies, not ACLs.
  block_public_acls   = true
  ignore_public_acls  = true

  # Dashboard is served as an S3 static website using a public bucket policy
  # scoped to the dashboard/ prefix. These two must stay false or the
  # S3 website endpoint returns 403 for all requests.
  block_public_policy     = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_lifecycle_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  rule {
    id     = "expire-athena-results"
    status = "Enabled"

    filter {
      prefix = "athena-results/"
    }

    expiration {
      days = 7
    }
  }

  # Expire raw stream NDJSON after 60 days — data is consumed into mart tables
  # by dbt within 24 hours of ingestion; 60-day window provides replay capacity.
  rule {
    id     = "expire-raw-stream"
    status = "Enabled"

    filter {
      prefix = "raw/stream/"
    }

    expiration {
      days = 60
    }
  }

  # Prevent S3 versioning from accumulating stale object versions indefinitely.
  # Applies to all prefixes: raw/, processed/.
  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }

  # Gap 7 (IoT Lens): Move processed/ Parquet files to S3 Intelligent-Tiering
  # from day 0. IT automatically demotes to Infrequent Access after 30 days of
  # no access (~40% storage cost reduction for cold partitions like 2023 data).
  # Retrieval from IA is synchronous — Athena queries are unaffected.
  # Archive tiers (3–5h latency) are NOT enabled, preserving Athena access.
  # Objects < 128 KB are not charged for IA transition (S3 IT minimum object size).
  rule {
    id     = "processed-intelligent-tiering"
    status = "Enabled"

    filter {
      prefix = "processed/"
    }

    transition {
      days          = 0
      storage_class = "INTELLIGENT_TIERING"
    }
  }
}

# ── Glue Data Catalog ─────────────────────────────────────────────────────────

resource "aws_glue_catalog_database" "openaq_raw" {
  name        = "openaq_raw"
  description = "OpenAQ raw measurements catalogued from S3 batch and stream prefixes"

  tags = local.common_tags
}

# ── Athena Workgroup ──────────────────────────────────────────────────────────

resource "aws_athena_workgroup" "openaq" {
  name        = "openaq_workgroup"
  description = "Athena workgroup for OpenAQ pipeline queries and dbt runs"

  configuration {
    enforce_workgroup_configuration    = false
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.main.bucket}/athena-results/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }

    bytes_scanned_cutoff_per_query = 10737418240 # 10 GB safety limit per query
    # Note: Athena query result reuse (60-min TTL) is not yet exposed by the
    # AWS Terraform provider. Enable manually: Athena console → Workgroups →
    # openaq_workgroup → Edit → Result reuse → Enable (60 minutes).
  }

  tags = local.common_tags
}

# ── Data Sources (current AWS account + region) ───────────────────────────────

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── IAM Role: openaq_pipeline_role ────────────────────────────────────────────
# NOTE: terraform-admin IAM user is pre-existing and is NOT declared here.
# This file manages only the runtime role assumed by EC2/Lambda/ECS tasks.

data "aws_iam_policy_document" "pipeline_assume_role" {
  statement {
    sid     = "AllowEC2Assume"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }

  statement {
    sid     = "AllowLambdaAssume"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "pipeline" {
  name               = "openaq_pipeline_role"
  assume_role_policy = data.aws_iam_policy_document.pipeline_assume_role.json

  tags = local.common_tags
}

data "aws_iam_policy_document" "pipeline_inline" {

  # S3 — project bucket (read/write)
  statement {
    sid    = "ProjectBucketReadWrite"
    effect = "Allow"

    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
    ]

    resources = [
      "${aws_s3_bucket.main.arn}/raw/*",
      "${aws_s3_bucket.main.arn}/processed/*",
      "${aws_s3_bucket.main.arn}/athena-results/*",
    ]
  }

  statement {
    sid    = "ProjectBucketList"
    effect = "Allow"

    actions = ["s3:ListBucket"]

    resources = [aws_s3_bucket.main.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["raw/*", "processed/*", "athena-results/*"]
    }
  }

  # S3 — OpenAQ public archive (read-only, requester-pays)
  statement {
    sid    = "OpenAQArchiveRead"
    effect = "Allow"

    actions = [
      "s3:GetObject",
    ]

    resources = [
      "arn:aws:s3:::openaq-data-archive/records/csv.gz/*",
    ]
  }

  statement {
    sid    = "OpenAQArchiveList"
    effect = "Allow"

    actions = ["s3:ListBucket"]

    resources = ["arn:aws:s3:::openaq-data-archive"]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["records/csv.gz/*"]
    }
  }

  # Glue — catalogue management
  statement {
    sid    = "GlueCatalogue"
    effect = "Allow"

    actions = [
      "glue:CreateTable",
      "glue:GetDatabase",
      "glue:GetTable",
      "glue:UpdateTable",
      "glue:GetPartition",
      "glue:GetPartitions",
      "glue:BatchCreatePartition",
    ]

    resources = [
      "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:catalog",
      "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:database/openaq_raw",
      "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:database/openaq_mart",
      "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/openaq_raw/*",
      "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/openaq_mart/*",
    ]
  }

  # Athena — query execution
  statement {
    sid    = "AthenaQuery"
    effect = "Allow"

    actions = [
      "athena:StartQueryExecution",
      "athena:GetQueryExecution",
      "athena:GetQueryResults",
      "athena:StopQueryExecution",
      "athena:GetWorkGroup",
    ]

    resources = [
      "arn:aws:athena:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:workgroup/openaq_workgroup",
    ]
  }

  # Kinesis — stream write
  statement {
    sid    = "KinesisStreamWrite"
    effect = "Allow"

    actions = [
      "kinesis:PutRecord",
      "kinesis:PutRecords",
      "kinesis:DescribeStream",
      "kinesis:DescribeStreamSummary",
    ]

    resources = [
      "arn:aws:kinesis:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:stream/openaq_stream",
    ]
  }

  # CloudWatch Logs — for Lambda execution logs
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = [
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/openaq_*",
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/openaq_*:*",
    ]
  }
}

resource "aws_iam_role_policy" "pipeline_inline" {
  name   = "openaq_pipeline_policy"
  role   = aws_iam_role.pipeline.id
  policy = data.aws_iam_policy_document.pipeline_inline.json
}

# ── Provider alias: us-east-1 ─────────────────────────────────────────────────
# Billing CloudWatch metrics are only available in us-east-1.
# Declared here (main.tf) to avoid provider conflict when lambda.tf is added.

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ── Locals ────────────────────────────────────────────────────────────────────

locals {
  bucket_name = "${var.project_name}-${var.s3_bucket_suffix}"

  # Single source of truth for all monitored Vietnamese station IDs.
  # Derived from the dbt seed transform/seeds/vn_stations.csv so the roster
  # cannot drift between the seed and the infra. Used by: Glue partition
  # projections (both tables), batch_sync env var, streaming_producer env var.
  # Weather_ingest embeds lat/lon per station and cannot be driven by this list
  # alone.
  stations        = csvdecode(file("${path.module}/../transform/seeds/vn_stations.csv"))
  station_ids_csv = join(",", [for s in local.stations : s.location_id])

  # Expected station count for the completeness check, derived from the seed
  # roster. Drives both the completeness Lambda EXPECTED_STATIONS env var and the
  # missing_stations alarm threshold (expected_stations - var.alert_threshold).
  expected_stations = length(local.stations)

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
  block_public_acls  = true
  ignore_public_acls = true

  # Dashboard is served as an S3 static website using a public bucket policy
  # scoped to the dashboard/ prefix. These two must stay false or the
  # S3 website endpoint returns 403 for all requests.
  block_public_policy     = false
  restrict_public_buckets = false
}

# ── S3 Static Website (Leaflet map) ──────────────────────────────────────────
# Enables the s3-website endpoint so dashboard/index.html is publicly browsable.
# Public read is scoped to the dashboard/ prefix only via the bucket policy below.

resource "aws_s3_bucket_website_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  index_document {
    suffix = "index.html"
  }

  # Must come after public_access_block or S3 rejects the website config
  depends_on = [aws_s3_bucket_public_access_block.main]
}

# Public read scoped to dashboard/ prefix only — all other prefixes (raw/,
# processed/, athena-results/) remain private.
resource "aws_s3_bucket_policy" "main" {
  bucket = aws_s3_bucket.main.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadDashboard"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.main.arn}/dashboard/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.main]
}

# ── Dashboard object: Terraform-managed upload of the Leaflet map (3.5) ───────
# Uploads dashboard/index.html with the real API Gateway endpoint substituted
# for the YOUR_API_GATEWAY_URL placeholder, so the page works without manual
# post-deploy editing. index.html reads `window.AQI_API_URL || "YOUR_API_GATEWAY_URL"`,
# so swapping the placeholder token is the least-invasive substitution and
# leaves the source file unmodified (no template markers required).
# source_hash forces re-upload whenever the file or the API endpoint changes.
resource "aws_s3_object" "dashboard_index" {
  bucket       = aws_s3_bucket.main.id
  key          = "dashboard/index.html"
  content_type = "text/html"

  content = replace(
    file("${path.module}/../dashboard/index.html"),
    "YOUR_API_GATEWAY_URL",
    aws_apigatewayv2_api.aqi_api.api_endpoint,
  )

  depends_on = [aws_s3_bucket_policy.main]

  tags = local.common_tags
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
    # NOT enforced. Enforcement forces ALL query output — including dbt CTAS table
    # data — under this workgroup's OutputLocation, and Athena REJECTS any CTAS
    # carrying an explicit external_location under an enforcing workgroup
    # (verified: "submitted to an Athena Workgroup that enforces a centralized
    # output location ... remove the 'external_location' property"). That trapped
    # the dbt marts under athena-results/, inheriting the 7-day expiry rule.
    # With enforcement off, dbt-athena writes marts to s3_data_dir (processed/,
    # Intelligent-Tiering) via external_location, off the expiry path entirely.
    # The 10 GB cutoff + result encryption below remain as workgroup DEFAULTS
    # (still applied to our pipeline/dbt queries, which never override them);
    # at-rest encryption is independently guaranteed by the bucket's default
    # SSE-S3 (AES256), and the $8 billing alarm backstops scan cost.
    enforce_workgroup_configuration    = false
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.main.bucket}/athena-results/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }

    bytes_scanned_cutoff_per_query = 10737418240 # 10 GB safety limit per query
  }

  tags = local.common_tags
}

# ── Post-deploy: Athena query result reuse ────────────────────────────────────
# The AWS Terraform provider (~> 5.0) does NOT expose query-result-reuse on the
# managed aws_athena_workgroup resource. Result reuse is an Athena per-query
# feature (StartQueryExecution ResultReuseConfiguration) and the only workgroup-
# level toggle (EnableQueryResultReuse) is reachable solely via the
# UpdateWorkGroup API / CLI — there is no corresponding workgroup argument.
# This null_resource therefore remains as the supported mechanism; it calls the
# AWS CLI once after the workgroup is created/updated.
# Idempotent: repeated UpdateWorkGroup calls with the same values are a no-op.
# Requires: AWS CLI installed and caller credentials with athena:UpdateWorkGroup.

resource "null_resource" "athena_result_reuse" {
  triggers = {
    workgroup_name  = aws_athena_workgroup.openaq.name
    max_age_minutes = "60"
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOC
      aws athena update-work-group \
        --work-group ${aws_athena_workgroup.openaq.name} \
        --configuration-updates '{"EnableQueryResultReuse":true,"QueryResultReuseConfiguration":{"MaxAgeInMinutes":60}}' \
        --region ${var.aws_region} \
        || echo "WARN: query result reuse not supported by this CLI version — non-fatal, continuing"
    EOC
  }
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

  # Glue — catalog management
  statement {
    sid    = "GlueCatalog"
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

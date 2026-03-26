# ── IAM Role: openaq_lambda_role ──────────────────────────────────────────────
# Dedicated execution role for both Lambda functions.
# (openaq_pipeline_role in main.tf is retained for EC2/future use.)

data "aws_iam_policy_document" "lambda_assume_role" {
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

resource "aws_iam_role" "lambda_exec" {
  name               = "openaq_lambda_role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = local.common_tags
}

data "aws_iam_policy_document" "lambda_inline" {

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

    actions = ["s3:GetObject"]

    resources = [
      "arn:aws:s3:::openaq-data-archive/records/csv.gz/*",
    ]
  }

  statement {
    sid    = "OpenAQArchiveList"
    effect = "Allow"

    actions = ["s3:ListBucket"]

    resources = ["arn:aws:s3:::openaq-data-archive"]
  }

  # Glue — catalogue read
  statement {
    sid    = "GlueCatalogueRead"
    effect = "Allow"

    actions = [
      "glue:GetDatabase",
      "glue:GetTable",
      "glue:GetPartitions",
    ]

    resources = [
      "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:catalog",
      "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:database/openaq_raw",
      "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/openaq_raw/*",
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
    ]

    resources = [
      "arn:aws:athena:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:workgroup/openaq_workgroup",
    ]
  }

  # Kinesis — stream write (streaming Lambda)
  statement {
    sid    = "KinesisStreamWrite"
    effect = "Allow"

    actions = [
      "kinesis:PutRecord",
      "kinesis:PutRecords",
      "kinesis:DescribeStream",
    ]

    resources = [
      "arn:aws:kinesis:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:stream/openaq_stream",
    ]
  }

  # CloudWatch Logs — Lambda execution logs
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

resource "aws_iam_role_policy" "lambda_inline" {
  name   = "openaq_lambda_policy"
  role   = aws_iam_role.lambda_exec.id
  policy = data.aws_iam_policy_document.lambda_inline.json
}

# ── CloudWatch Log Groups ──────────────────────────────────────────────────────
# Pre-created so logs persist if functions are destroyed and recreated.

resource "aws_cloudwatch_log_group" "batch_sync" {
  name              = "/aws/lambda/openaq_batch_sync"
  retention_in_days = 14

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "streaming_producer" {
  name              = "/aws/lambda/openaq_streaming_producer"
  retention_in_days = 14

  tags = local.common_tags
}

# ── Lambda: openaq_batch_sync ─────────────────────────────────────────────────
# Syncs current month's archive files to raw/batch/ for all 21 VN stations.
# Triggered daily at 01:00 UTC by EventBridge Scheduler.
# Timeout 900s covers aws s3 sync cross-region (us-east-1 → ap-southeast-1).

resource "aws_lambda_function" "batch_sync" {
  function_name = "openaq_batch_sync"
  role          = aws_iam_role.lambda_exec.arn
  runtime       = "python3.12"
  handler       = "handler.handler"
  filename      = var.lambda_batch_zip_path
  timeout       = 900
  memory_size   = 512

  environment {
    variables = {
      S3_BUCKET_NAME = local.bucket_name
    }
  }

  depends_on = [aws_cloudwatch_log_group.batch_sync]

  tags = local.common_tags
}

# ── Lambda: openaq_streaming_producer ─────────────────────────────────────────
# Fetches latest readings from OpenAQ v3 API and publishes to Kinesis.
# Triggered every 30 minutes by EventBridge Scheduler.
# AWS_REGION is injected automatically by the Lambda runtime — not set here
# (setting a reserved Lambda env var causes an API error on apply).

resource "aws_lambda_function" "streaming_producer" {
  function_name = "openaq_streaming_producer"
  role          = aws_iam_role.lambda_exec.arn
  runtime       = "python3.12"
  handler       = "handler.handler"
  filename      = var.lambda_streaming_zip_path
  timeout       = 120
  memory_size   = 256

  environment {
    variables = {
      OPENAQ_API_KEY      = var.openaq_api_key
      KINESIS_STREAM_NAME = aws_kinesis_stream.openaq.name
    }
  }

  depends_on = [aws_cloudwatch_log_group.streaming_producer]

  tags = local.common_tags
}

# ── IAM Role: openaq_scheduler_role ───────────────────────────────────────────

data "aws_iam_policy_document" "scheduler_assume_role" {
  statement {
    sid     = "AllowSchedulerAssume"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "scheduler" {
  name               = "openaq_scheduler_role"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume_role.json

  tags = local.common_tags
}

data "aws_iam_policy_document" "scheduler_invoke" {
  statement {
    sid    = "InvokeLambdas"
    effect = "Allow"

    actions = ["lambda:InvokeFunction"]

    resources = [
      aws_lambda_function.batch_sync.arn,
      aws_lambda_function.streaming_producer.arn,
    ]
  }
}

resource "aws_iam_role_policy" "scheduler_invoke" {
  name   = "openaq_scheduler_invoke"
  role   = aws_iam_role.scheduler.id
  policy = data.aws_iam_policy_document.scheduler_invoke.json
}

# ── EventBridge Scheduler: daily batch sync ───────────────────────────────────
# 01:00 UTC daily. The ? in the cron expression is required by EventBridge
# Scheduler (day-of-week must be ? when day-of-month is *).

resource "aws_scheduler_schedule" "batch_daily" {
  name       = "openaq_batch_daily"
  group_name = "default"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression = "cron(0 1 * * ? *)"

  target {
    arn      = aws_lambda_function.batch_sync.arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({})
  }
}

# ── EventBridge Scheduler: 30-minute streaming ────────────────────────────────

resource "aws_scheduler_schedule" "streaming_30min" {
  name       = "openaq_streaming_30min"
  group_name = "default"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression = "cron(0/30 * * * ? *)"

  target {
    arn      = aws_lambda_function.streaming_producer.arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({})
  }
}

# ── SNS event-driven batch sync (Improvement 3) ───────────────────────────────
#
# OpenAQ publishes an SNS notification to:
#   arn:aws:sns:us-east-1:817926761842:openaq-data-archive-object_created
# for every new CSV.GZ written to the archive bucket.
#
# Architecture:
#   SNS (us-east-1) → SQS (us-east-1) → Lambda (ap-southeast-1, cross-region trigger)
#
# This replaces the cron-based daily batch for files that arrive during the day;
# the cron schedule is retained as a catch-all for any missed events.
#
# NOTE: The SNS topic is owned by OpenAQ (account 817926761842) and is in
# us-east-1. Resources below are ap-southeast-1 except where noted.

# SQS queue in us-east-1 to buffer SNS notifications
resource "aws_sqs_queue" "openaq_events" {
  provider = aws.us_east_1
  name     = "openaq-archive-events"

  # Keep messages for 4 hours — Lambda will drain quickly under normal load
  message_retention_seconds  = 14400
  visibility_timeout_seconds = 960   # > Lambda timeout (900s) to prevent double-processing

  tags = local.common_tags
}

# Allow the OpenAQ SNS topic to send messages to our queue
resource "aws_sqs_queue_policy" "openaq_events" {
  provider  = aws.us_east_1
  queue_url = aws_sqs_queue.openaq_events.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowOpenAQSNS"
      Effect    = "Allow"
      Principal = { Service = "sns.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.openaq_events.arn
      Condition = {
        ArnEquals = {
          "aws:SourceArn" = "arn:aws:sns:us-east-1:817926761842:openaq-data-archive-object_created"
        }
      }
    }]
  })
}

# Subscribe batch_sync Lambda directly to the OpenAQ SNS topic.
# SNS cross-region Lambda invocation is supported (Lambda endpoint may be in
# a different region from the SNS topic since 2021).
# The SQS queue is retained for buffering but not wired as a Lambda trigger —
# Lambda is invoked directly by SNS, which retries 3 times on failure.
resource "aws_sns_topic_subscription" "openaq_events" {
  provider  = aws.us_east_1
  topic_arn = "arn:aws:sns:us-east-1:817926761842:openaq-data-archive-object_created"
  protocol  = "lambda"
  endpoint  = aws_lambda_function.batch_sync.arn
}

# Allow the OpenAQ SNS topic to invoke the batch_sync Lambda
resource "aws_lambda_permission" "sns_invoke_batch" {
  statement_id  = "AllowOpenAQSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.batch_sync.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = "arn:aws:sns:us-east-1:817926761842:openaq-data-archive-object_created"
}

# ── Lambda: openaq_aqi_api ─────────────────────────────────────────────────────
# HTTP API returning latest composite AQI per station as GeoJSON.
# Consumed by dashboard/index.html Leaflet map.

resource "aws_cloudwatch_log_group" "aqi_api" {
  name              = "/aws/lambda/openaq_aqi_api"
  retention_in_days = 14
  tags              = local.common_tags
}

resource "aws_lambda_function" "aqi_api" {
  function_name = "openaq_aqi_api"
  role          = aws_iam_role.lambda_exec.arn
  runtime       = "python3.12"
  handler       = "handler.handler"
  filename      = var.lambda_aqi_api_zip_path
  timeout       = 60
  memory_size   = 256

  environment {
    variables = {
      S3_BUCKET_NAME    = local.bucket_name
      ATHENA_DATABASE   = "openaq_mart"
      ATHENA_WORKGROUP  = "openaq_workgroup"
    }
  }

  depends_on = [aws_cloudwatch_log_group.aqi_api]
  tags       = local.common_tags
}

# Lambda Function URL — public HTTPS endpoint, no API Gateway needed
resource "aws_lambda_function_url" "aqi_api" {
  function_name      = aws_lambda_function.aqi_api.function_name
  authorization_type = "NONE"   # public read-only endpoint; AQI data is not sensitive

  cors {
    allow_origins = ["*"]
    allow_methods = ["GET"]
    max_age       = 3600
  }
}

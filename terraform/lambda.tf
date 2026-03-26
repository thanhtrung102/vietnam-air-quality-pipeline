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

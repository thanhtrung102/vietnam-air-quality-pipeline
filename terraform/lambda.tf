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

  # S3 — weather raw prefix write (weather_ingest Lambda)
  # Scoped separately so future policy refactoring can restrict weather writes
  # without affecting the broader raw/* grant above.
  statement {
    sid    = "WeatherRawWrite"
    effect = "Allow"

    actions = ["s3:PutObject"]

    resources = ["${aws_s3_bucket.main.arn}/raw/weather/*"]
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

  # Athena requires GetBucketLocation to verify the query output bucket
  statement {
    sid     = "ProjectBucketLocation"
    effect  = "Allow"
    actions = ["s3:GetBucketLocation"]
    resources = [aws_s3_bucket.main.arn]
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
      "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:database/openaq_mart",
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

  # SQS — DLQ for streaming Lambda (Gap 1: IoT Lens dead-letter queue)
  statement {
    sid    = "StreamingDLQSend"
    effect = "Allow"

    actions = ["sqs:SendMessage"]

    resources = [aws_sqs_queue.streaming_dlq.arn]
  }

  # Secrets Manager — retrieve OPENAQ_API_KEY (Gap 2: IoT Lens secrets rotation)
  statement {
    sid    = "SecretsManagerGetApiKey"
    effect = "Allow"

    actions = ["secretsmanager:GetSecretValue"]

    resources = [aws_secretsmanager_secret.openaq_api_key.arn]
  }

  # CloudWatch Metrics — custom pipeline metrics (Gap 3: validation rejections; Gap 6: completeness)
  statement {
    sid    = "CloudWatchPutMetrics"
    effect = "Allow"

    actions = ["cloudwatch:PutMetricData"]

    resources = ["*"]
    # cloudwatch:PutMetricData does not support resource-level restrictions
  }

  # SNS — publish alerts for completeness check (Gap 6)
  statement {
    sid    = "SNSPublishAlerts"
    effect = "Allow"

    actions = ["sns:Publish"]

    resources = [aws_sns_topic.openaq_alerts.arn]
  }
}

resource "aws_iam_role_policy" "lambda_inline" {
  name   = "openaq_lambda_policy"
  role   = aws_iam_role.lambda_exec.id
  policy = data.aws_iam_policy_document.lambda_inline.json
}

# ── SQS Dead Letter Queue: streaming Lambda (Gap 1 — IoT Lens) ───────────────
# Captures failed Kinesis PutRecord events and API fetch failures that cause the
# Lambda to crash (unhandled exception). Visibility timeout must exceed Lambda
# timeout (120s) to prevent the same message being reprocessed while in-flight.

resource "aws_sqs_queue" "streaming_dlq" {
  name                       = "openaq_streaming_dlq"
  message_retention_seconds  = 86400            # 1 day — operator drains manually
  visibility_timeout_seconds = 130              # > Lambda timeout (120s)

  tags = local.common_tags
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
      STATION_IDS    = local.station_ids_csv
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

  # Gap 1 (IoT Lens): Dead Letter Queue captures unhandled Lambda failures.
  # On crash (unhandled exception), the failed event JSON is sent to this queue.
  dead_letter_config {
    target_arn = aws_sqs_queue.streaming_dlq.arn
  }

  environment {
    variables = {
      # Gap 2 (IoT Lens): API key is now read from Secrets Manager at runtime
      # (see lambda/streaming/handler.py _get_api_key()). OPENAQ_API_KEY env var
      # is retained as an emergency fallback for local testing only — do NOT
      # set it in production after secrets.tf is applied.
      OPENAQ_API_KEY        = var.openaq_api_key
      OPENAQ_SECRET_NAME    = aws_secretsmanager_secret.openaq_api_key.name
      KINESIS_STREAM_NAME   = aws_kinesis_stream.openaq.name
      STATION_IDS           = local.station_ids_csv
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
      CACHE_TTL_SECONDS = "3600"
    }
  }

  depends_on = [aws_cloudwatch_log_group.aqi_api]
  tags       = local.common_tags
}

# ── HTTP API Gateway: public endpoint for openaq_aqi_api ──────────────────────
# Lambda Function URLs with AuthType=NONE are blocked by AWS account-level
# Block Public Access (default-on for accounts created after Nov 2024).
# HTTP API Gateway bypasses this restriction and provides the same public HTTPS
# endpoint with CORS — no auth, read-only AQI data.

resource "aws_apigatewayv2_api" "aqi_api" {
  name          = "openaq-aqi-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET"]
    max_age       = 3600
  }

  tags = local.common_tags
}

resource "aws_apigatewayv2_integration" "aqi_api" {
  api_id                 = aws_apigatewayv2_api.aqi_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.aqi_api.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "aqi_api" {
  api_id    = aws_apigatewayv2_api.aqi_api.id
  route_key = "GET /"
  target    = "integrations/${aws_apigatewayv2_integration.aqi_api.id}"
}

resource "aws_apigatewayv2_stage" "aqi_api" {
  api_id      = aws_apigatewayv2_api.aqi_api.id
  name        = "$default"
  auto_deploy = true

  tags = local.common_tags
}

resource "aws_lambda_permission" "aqi_api_apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.aqi_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.aqi_api.execution_arn}/*"
}

# ── Lambda: openaq_completeness_check (Gap 6 — IoT Lens) ──────────────────────
# Runs hourly. Queries mart_daily_aqi to count distinct active stations for
# today. Emits CloudWatch metric MissingStations (namespace: OpenAQ/Pipeline).
# If coverage < 18/21 stations (< 85%) for 2 consecutive hours → SNS alert.

resource "aws_cloudwatch_log_group" "completeness_check" {
  name              = "/aws/lambda/openaq_completeness_check"
  retention_in_days = 14
  tags              = local.common_tags
}

resource "aws_lambda_function" "completeness_check" {
  function_name = "openaq_completeness_check"
  role          = aws_iam_role.lambda_exec.arn
  runtime       = "python3.12"
  handler       = "handler.handler"
  filename      = var.lambda_completeness_zip_path
  timeout       = 120
  memory_size   = 256

  environment {
    variables = {
      S3_BUCKET_NAME      = local.bucket_name
      ATHENA_DATABASE     = "openaq_mart"
      ATHENA_WORKGROUP    = "openaq_workgroup"
      EXPECTED_STATIONS   = "21"
      ALERT_THRESHOLD     = "18"          # < 18 = alert (85% coverage floor)
      SNS_ALERT_TOPIC_ARN = aws_sns_topic.openaq_alerts.arn
    }
  }

  depends_on = [aws_cloudwatch_log_group.completeness_check]
  tags       = local.common_tags
}

resource "aws_scheduler_schedule" "completeness_hourly" {
  name       = "openaq_completeness_hourly"
  group_name = "default"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression = "cron(0 * * * ? *)"   # top of every hour

  target {
    arn      = aws_lambda_function.completeness_check.arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({})
  }
}

resource "aws_lambda_permission" "completeness_scheduler" {
  statement_id  = "AllowSchedulerInvokeCompleteness"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.completeness_check.function_name
  principal     = "scheduler.amazonaws.com"
  source_arn    = aws_scheduler_schedule.completeness_hourly.arn
}

# Allow scheduler to invoke completeness Lambda
resource "aws_iam_role_policy" "scheduler_invoke_completeness" {
  name = "openaq_scheduler_invoke_completeness"
  role = aws_iam_role.scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "InvokeCompleteness"
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = aws_lambda_function.completeness_check.arn
    }]
  })
}

# ── CloudWatch Alarm: MissingStations (Gap 6) ─────────────────────────────────
# Fires when > 3 stations are missing for 2 consecutive 1-hour periods.

resource "aws_cloudwatch_metric_alarm" "missing_stations" {
  alarm_name          = "openaq_missing_stations"
  alarm_description   = "More than 3 VN stations are missing from mart_daily_aqi for the current date"
  metric_name         = "MissingStations"
  namespace           = "OpenAQ/Pipeline"
  statistic           = "Maximum"
  period              = 3600          # 1-hour evaluation window
  evaluation_periods  = 2             # alarm after 2 consecutive breaches
  threshold           = 3
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.openaq_alerts.arn]

  tags = local.common_tags
}

# ── Lambda: openaq_weather_ingest (Phase 3 — Weather Data Ingestion) ──────────
# Fetches previous day's hourly ERA5 weather from Open-Meteo for all 21 VN
# station coordinates and writes NDJSON to raw/weather/.
# Triggered daily at 02:00 UTC (after Open-Meteo ERA5 ~5-day lag allows
# yesterday's data to be available and processed).
# BACKFILL_DAYS env var enables retroactive catch-up; set via Lambda console.

resource "aws_cloudwatch_log_group" "weather_ingest" {
  name              = "/aws/lambda/openaq_weather_ingest"
  retention_in_days = 14
  tags              = local.common_tags
}

resource "aws_lambda_function" "weather_ingest" {
  function_name = "openaq_weather_ingest"
  role          = aws_iam_role.lambda_exec.arn
  runtime       = "python3.12"
  handler       = "handler.handler"
  filename      = var.lambda_weather_zip_path
  timeout       = 300   # 21 stations × ~2s/req + S3 writes; 5 min is comfortable
  memory_size   = 256

  environment {
    variables = {
      S3_BUCKET_NAME = local.bucket_name
      BACKFILL_DAYS  = "1"   # default: yesterday only; override via event payload
    }
  }

  depends_on = [aws_cloudwatch_log_group.weather_ingest]
  tags       = local.common_tags
}

resource "aws_scheduler_schedule" "weather_daily" {
  name       = "openaq_weather_daily"
  group_name = "default"

  flexible_time_window {
    mode = "OFF"
  }

  # 02:00 UTC daily — after ERA5 reanalysis lag and well before dbt 03:00 run
  schedule_expression = "cron(0 2 * * ? *)"

  target {
    arn      = aws_lambda_function.weather_ingest.arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({})
  }
}

resource "aws_lambda_permission" "weather_scheduler" {
  statement_id  = "AllowSchedulerInvokeWeather"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.weather_ingest.function_name
  principal     = "scheduler.amazonaws.com"
  source_arn    = aws_scheduler_schedule.weather_daily.arn
}

resource "aws_iam_role_policy" "scheduler_invoke_weather" {
  name = "openaq_scheduler_invoke_weather"
  role = aws_iam_role.scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "InvokeWeather"
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = aws_lambda_function.weather_ingest.arn
    }]
  })
}

# ── ECR Repository: forecast_generate container image (Phase 5) ───────────────
# statsmodels + prophet + pandas + pyarrow exceed the 250 MB Lambda zip limit.
# The forecast Lambda is therefore deployed as a container image via ECR.
#
# Deployment order:
#   1. terraform apply   → creates ECR repo (forecast Lambda is skipped on first
#                           apply because forecast_lambda_image_uri is empty by default)
#   2. docker build && docker push  (see lambda/forecast_generate/Dockerfile)
#   3. terraform apply -var="forecast_lambda_image_uri=<ECR_URI>:latest"

resource "aws_ecr_repository" "forecast" {
  name                 = "openaq-forecast-generate"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.common_tags
}

resource "aws_ecr_lifecycle_policy" "forecast" {
  repository = aws_ecr_repository.forecast.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Retain last 3 images to allow rollback"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 3
      }
      action = { type = "expire" }
    }]
  })
}

# ── Lambda: openaq_forecast_generate (Phase 5) ────────────────────────────────
# Container image Lambda. Created only when forecast_lambda_image_uri is non-empty.
# Runs after weather_ingest (02:00 UTC) and dbt (assumed ~02:30 UTC): scheduled 03:00 UTC.
# 3 GB memory for statsmodels + Prophet; 15 min timeout for 21 stations × 2 models.

resource "aws_cloudwatch_log_group" "forecast_generate" {
  count             = var.forecast_lambda_image_uri != "" ? 1 : 0
  name              = "/aws/lambda/openaq_forecast_generate"
  retention_in_days = 14
  tags              = local.common_tags
}

resource "aws_lambda_function" "forecast_generate" {
  count         = var.forecast_lambda_image_uri != "" ? 1 : 0
  function_name = "openaq_forecast_generate"
  role          = aws_iam_role.lambda_exec.arn
  package_type  = "Image"
  image_uri     = var.forecast_lambda_image_uri
  timeout       = 900    # 15 minutes — SARIMA for 21 stations (Prophet removed: cmdstanpy incompatibility)
  memory_size   = 3008   # 3 GB — statsmodels + numpy/pandas/pyarrow in-memory model objects

  environment {
    variables = {
      S3_BUCKET_NAME      = local.bucket_name
      ATHENA_DATABASE     = "openaq_mart"
      ATHENA_WORKGROUP    = "openaq_workgroup"
      SNS_ALERT_TOPIC_ARN = aws_sns_topic.openaq_alerts.arn
      FORECAST_HORIZON    = "7"
      HOLDOUT_DAYS        = "30"
      MIN_TRAIN_DAYS      = "60"
    }
  }

  depends_on = [aws_cloudwatch_log_group.forecast_generate]
  tags       = local.common_tags
}

resource "aws_scheduler_schedule" "forecast_daily" {
  count      = var.forecast_lambda_image_uri != "" ? 1 : 0
  name       = "openaq_forecast_daily"
  group_name = "default"

  flexible_time_window {
    mode = "OFF"
  }

  # 03:00 UTC — after weather_ingest (02:00) and dbt mart rebuild (~02:30)
  schedule_expression = "cron(0 3 * * ? *)"

  target {
    arn      = aws_lambda_function.forecast_generate[0].arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({})
  }
}

resource "aws_lambda_permission" "forecast_scheduler" {
  count         = var.forecast_lambda_image_uri != "" ? 1 : 0
  statement_id  = "AllowSchedulerInvokeForecast"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.forecast_generate[0].function_name
  principal     = "scheduler.amazonaws.com"
  source_arn    = aws_scheduler_schedule.forecast_daily[0].arn
}

resource "aws_iam_role_policy" "scheduler_invoke_forecast" {
  count = var.forecast_lambda_image_uri != "" ? 1 : 0
  name  = "openaq_scheduler_invoke_forecast"
  role  = aws_iam_role.scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "InvokeForecast"
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = aws_lambda_function.forecast_generate[0].arn
    }]
  })
}

# ── CloudWatch Alarm: ForecastRMSE (Phase 5.5) ────────────────────────────────
# Fires when SARIMA holdout RMSE for Hanoi exceeds 25 µg/m³ (model drift indicator).
# The forecast Lambda emits ForecastRMSE{Model=sarima, City=Hanoi} after each run.

resource "aws_cloudwatch_metric_alarm" "forecast_rmse_sarima" {
  count               = var.forecast_lambda_image_uri != "" ? 1 : 0
  alarm_name          = "openaq_forecast_rmse_sarima_hanoi"
  alarm_description   = "SARIMA 30-day holdout RMSE for Hanoi > 25 µg/m³ — model may need retraining"
  metric_name         = "ForecastRMSE"
  namespace           = "OpenAQ/Pipeline"
  statistic           = "Average"
  period              = 86400         # 1-day evaluation (Lambda runs once daily)
  evaluation_periods  = 3             # alert after 3 consecutive breaches
  threshold           = 25
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    Model = "sarima"
    City  = "Hanoi"
  }

  alarm_actions = [aws_sns_topic.openaq_alerts.arn]

  tags = local.common_tags
}

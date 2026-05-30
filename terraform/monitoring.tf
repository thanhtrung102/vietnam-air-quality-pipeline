# ── SNS Topic for Alerts ──────────────────────────────────────────────────────

resource "aws_sns_topic" "openaq_alerts" {
  name = "openaq_alerts"

  tags = local.common_tags
}

resource "aws_sns_topic_subscription" "alert_email" {
  topic_arn = aws_sns_topic.openaq_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ── CloudWatch Alarm: Kinesis Iterator Age ────────────────────────────────────
# Fires when consumers fall behind > 5 minutes, indicating a processing backlog.

resource "aws_cloudwatch_metric_alarm" "kinesis_iterator_age" {
  alarm_name          = "openaq-kinesis-iterator-age-high"
  alarm_description   = "Kinesis consumer iterator age exceeds 5 minutes — stream consumer is falling behind"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "GetRecords.IteratorAgeMilliseconds"
  namespace           = "AWS/Kinesis"
  period              = 300
  statistic           = "Maximum"
  threshold           = 300000 # 5 minutes in ms

  dimensions = {
    StreamName = aws_kinesis_stream.openaq.name
  }

  alarm_actions = [aws_sns_topic.openaq_alerts.arn]
  ok_actions    = [aws_sns_topic.openaq_alerts.arn]

  treat_missing_data = "notBreaching"

  tags = local.common_tags
}

# ── CloudWatch Alarm: Estimated Billing ───────────────────────────────────────
# Billing metrics are only available in us-east-1.

resource "aws_cloudwatch_metric_alarm" "billing" {
  provider = aws.us_east_1

  alarm_name          = "openaq-monthly-spend-high"
  alarm_description   = "Estimated AWS charges exceed $8 for the month"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "EstimatedCharges"
  namespace           = "AWS/Billing"
  period              = 86400 # 24 hours (billing metrics update daily)
  statistic           = "Maximum"
  threshold           = 8

  dimensions = {
    Currency = "USD"
  }

  alarm_actions = [aws_sns_topic.openaq_alerts_us.arn]

  treat_missing_data = "notBreaching"

  tags = local.common_tags
}

# Billing alarm requires us-east-1 provider alias and a us-east-1 SNS topic
resource "aws_sns_topic" "openaq_alerts_us" {
  provider = aws.us_east_1
  name     = "openaq_alerts_billing"

  tags = local.common_tags
}

resource "aws_sns_topic_subscription" "alert_email_billing" {
  provider  = aws.us_east_1
  topic_arn = aws_sns_topic.openaq_alerts_us.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ── CloudWatch Dashboard ──────────────────────────────────────────────────────

resource "aws_cloudwatch_dashboard" "openaq_pipeline" {
  dashboard_name = "openaq_pipeline"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Kinesis IncomingRecords (24h)"
          period = 300
          stat   = "Sum"
          view   = "timeSeries"
          region = var.aws_region
          metrics = [
            [
              "AWS/Kinesis",
              "IncomingRecords",
              "StreamName",
              aws_kinesis_stream.openaq.name
            ]
          ]
          yAxis = {
            left = { min = 0 }
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "S3 NumberOfObjects — processed/ (7 days)"
          period = 86400
          stat   = "Average"
          view   = "timeSeries"
          region = var.aws_region
          metrics = [
            [
              "AWS/S3",
              "NumberOfObjects",
              "BucketName",
              aws_s3_bucket.main.bucket,
              "FilterId",
              "processed-prefix",
              "StorageType",
              "AllStorageTypes"
            ]
          ]
          yAxis = {
            left = { min = 0 }
          }
        }
      }
    ]
  })
}

# ── CloudWatch Alarm: CodeBuild dbt runner failed (WAF OPS 9) ─────────────────
# Fires when any dbt run fails, alerting before mart tables go stale.
# FailedBuilds is a CodeBuild native metric — no log filter required.

resource "aws_cloudwatch_metric_alarm" "codebuild_failed" {
  alarm_name          = "openaq-dbt-runner-failed"
  alarm_description   = "openaq-dbt-runner CodeBuild build failed — dbt mart tables may be stale"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FailedBuilds"
  namespace           = "AWS/CodeBuild"
  period              = 3600
  statistic           = "Sum"
  threshold           = 0

  dimensions = {
    ProjectName = aws_codebuild_project.dbt_runner.name
  }

  alarm_actions      = [aws_sns_topic.openaq_alerts.arn]
  treat_missing_data = "notBreaching"

  tags = local.common_tags
}

# S3 metrics filter for processed/ prefix
resource "aws_s3_bucket_metric" "processed_prefix" {
  bucket = aws_s3_bucket.main.id
  name   = "processed-prefix"

  filter {
    prefix = "processed/"
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# Silent-failure observability (architecture-evaluation HIGH findings)
#
# Before these alarms the orchestration layer could fail silently: batch_sync and
# weather_ingest return success even when every station errors, and the only
# freshness signal (completeness_check SNS) self-suppresses once data_age > 7d —
# i.e. it goes quiet in exactly the "pipeline is dead" case. The handlers now emit
# BatchStationFailures / WeatherIngestErrors / DaysSinceLastNewMart custom metrics;
# the alarms below page on them, plus direct Lambda-error and DLQ-depth alarms.
# ──────────────────────────────────────────────────────────────────────────────

# Batch sync: any station failing its archive sweep is silent data loss.
resource "aws_cloudwatch_metric_alarm" "batch_station_failures" {
  alarm_name          = "openaq-batch-station-failures"
  alarm_description   = "openaq_batch_sync reported >=1 failed station — archive data for that station is not being synced"
  namespace           = "OpenAQ/Pipeline"
  metric_name         = "BatchStationFailures"
  statistic           = "Maximum"
  period              = 86400 # batch runs once daily (01:00 UTC)
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.openaq_alerts.arn]
  ok_actions    = [aws_sns_topic.openaq_alerts.arn]

  tags = local.common_tags
}

# Weather ingest: tolerate the odd transient single-station failure, but page on a
# systemic Open-Meteo outage (>5 of 21 stations failing in one run) that would
# silently starve the weather + forecast marts.
resource "aws_cloudwatch_metric_alarm" "weather_ingest_errors" {
  alarm_name          = "openaq-weather-ingest-errors"
  alarm_description   = "openaq_weather_ingest failed for >5 stations in one run — systemic Open-Meteo outage degrading weather/forecast marts"
  namespace           = "OpenAQ/Pipeline"
  metric_name         = "WeatherIngestErrors"
  statistic           = "Maximum"
  period              = 86400 # weather runs once daily (02:00 UTC)
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.openaq_alerts.arn]

  tags = local.common_tags
}

# Mart freshness — the true "pipeline silently dead" signal that the SNS
# stale-suppression mutes. Healthy steady state runs ~10 days behind today
# (OpenAQ archive publish lag + 3-month batch window), so the threshold is set
# generously at 21 days: only a stalled mart (gap growing unbounded) trips it.
resource "aws_cloudwatch_metric_alarm" "mart_freshness" {
  alarm_name          = "openaq-mart-stale"
  alarm_description   = "mart_daily_aqi newest measurement_date is >21 days old — dbt build has likely stalled (silent-death signal the SNS path suppresses)"
  namespace           = "OpenAQ/Pipeline"
  metric_name         = "DaysSinceLastNewMart"
  statistic           = "Maximum"
  period              = 3600
  evaluation_periods  = 2 # 2 consecutive hourly checks, to ride out a transient Athena failure
  threshold           = 21
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching" # completeness Lambda errors are covered by its own alarm below

  alarm_actions = [aws_sns_topic.openaq_alerts.arn]
  ok_actions    = [aws_sns_topic.openaq_alerts.arn]

  tags = local.common_tags
}

# Direct Lambda Errors alarms — previously only indirect/lagging proxies existed.
locals {
  lambda_error_alarm_targets = {
    aqi_api            = aws_lambda_function.aqi_api.function_name
    streaming_producer = aws_lambda_function.streaming_producer.function_name
    batch_sync         = aws_lambda_function.batch_sync.function_name
    weather_ingest     = aws_lambda_function.weather_ingest.function_name
    completeness_check = aws_lambda_function.completeness_check.function_name
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = local.lambda_error_alarm_targets

  alarm_name          = "openaq-${each.key}-errors"
  alarm_description   = "${each.value} reported >=1 invocation error"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = each.value
  }

  alarm_actions = [aws_sns_topic.openaq_alerts.arn]

  tags = local.common_tags
}

# aqi_api is the only public, unthrottled entry point — alarm on throttling so a
# traffic spike that starves the shared Lambda concurrency pool is visible.
resource "aws_cloudwatch_metric_alarm" "aqi_api_throttles" {
  alarm_name          = "openaq-aqi-api-throttles"
  alarm_description   = "${aws_lambda_function.aqi_api.function_name} is being throttled — public API hitting the concurrency ceiling"
  namespace           = "AWS/Lambda"
  metric_name         = "Throttles"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.aqi_api.function_name
  }

  alarm_actions = [aws_sns_topic.openaq_alerts.arn]

  tags = local.common_tags
}

# DLQ depth — any message landing in a dead-letter queue is an unrecovered
# failure that needs an operator. The DLQs existed but nothing watched them.
resource "aws_cloudwatch_metric_alarm" "dlq_depth" {
  for_each = {
    streaming  = aws_sqs_queue.streaming_dlq.name
    batch_sync = aws_sqs_queue.batch_sync_dlq.name
  }

  alarm_name          = "openaq-${each.key}-dlq-depth"
  alarm_description   = "Messages present in ${each.value} — an invocation failed and was dead-lettered"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = each.value
  }

  alarm_actions = [aws_sns_topic.openaq_alerts.arn]

  tags = local.common_tags
}

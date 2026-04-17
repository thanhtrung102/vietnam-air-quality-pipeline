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

# ── Kinesis Data Stream ───────────────────────────────────────────────────────

resource "aws_kinesis_stream" "openaq" {
  name             = "openaq_stream"
  retention_period = 168 # 7 days — allows replay if Firehose delivery fails

  # ON_DEMAND scales automatically and is significantly cheaper than PROVISIONED
  # for sparse workloads (21 stations × 30-min polling ≈ a few KB/hour).
  # shard_count must be omitted in ON_DEMAND mode.
  stream_mode_details {
    stream_mode = "ON_DEMAND"
  }

  tags = local.common_tags
}

# ── IAM Role for Kinesis Firehose ─────────────────────────────────────────────

data "aws_iam_policy_document" "firehose_assume_role" {
  statement {
    sid     = "AllowFirehoseAssume"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["firehose.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "firehose" {
  name               = "openaq_firehose_role"
  assume_role_policy = data.aws_iam_policy_document.firehose_assume_role.json

  tags = local.common_tags
}

data "aws_iam_policy_document" "firehose_inline" {

  # Read from the Kinesis stream
  statement {
    sid    = "ReadKinesisStream"
    effect = "Allow"

    actions = [
      "kinesis:GetRecords",
      "kinesis:GetShardIterator",
      "kinesis:DescribeStream",
      "kinesis:DescribeStreamSummary",
      "kinesis:ListShards",
      "kinesis:SubscribeToShard",
    ]

    resources = [
      aws_kinesis_stream.openaq.arn,
    ]
  }

  # Write to the project S3 bucket under raw/stream/
  statement {
    sid    = "WriteS3Stream"
    effect = "Allow"

    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:ListBucketMultipartUploads",
      "s3:AbortMultipartUpload",
      "s3:ListBucket",
    ]

    resources = [
      aws_s3_bucket.main.arn,
      "${aws_s3_bucket.main.arn}/raw/stream/*",
    ]
  }

  # CloudWatch Logs for Firehose error logging
  statement {
    sid    = "FirehoseCloudWatchLogs"
    effect = "Allow"

    actions = [
      "logs:PutLogEvents",
    ]

    resources = [
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/kinesisfirehose/openaq_firehose:*",
    ]
  }
}

resource "aws_iam_role_policy" "firehose_inline" {
  name   = "openaq_firehose_policy"
  role   = aws_iam_role.firehose.id
  policy = data.aws_iam_policy_document.firehose_inline.json
}

# ── CloudWatch Log Group for Firehose errors ──────────────────────────────────

resource "aws_cloudwatch_log_group" "firehose" {
  name              = "/aws/kinesisfirehose/openaq_firehose"
  retention_in_days = 14

  tags = local.common_tags
}

resource "aws_cloudwatch_log_stream" "firehose_s3" {
  name           = "S3Delivery"
  log_group_name = aws_cloudwatch_log_group.firehose.name
}

# ── Kinesis Firehose Delivery Stream ─────────────────────────────────────────

resource "aws_kinesis_firehose_delivery_stream" "openaq" {
  name        = "openaq_firehose"
  destination = "extended_s3"

  kinesis_source_configuration {
    kinesis_stream_arn = aws_kinesis_stream.openaq.arn
    role_arn           = aws_iam_role.firehose.arn
  }

  extended_s3_configuration {
    role_arn           = aws_iam_role.firehose.arn
    bucket_arn         = aws_s3_bucket.main.arn
    prefix             = "raw/stream/!{timestamp:yyyy}/!{timestamp:MM}/!{timestamp:dd}/!{timestamp:HH}/"
    error_output_prefix = "raw/stream-errors/!{firehose:error-output-type}/!{timestamp:yyyy}/!{timestamp:MM}/!{timestamp:dd}/"

    buffering_size     = 128
    buffering_interval = 300
    compression_format = "GZIP" # ~70% storage reduction; JsonSerDe reads GZIP transparently

    s3_backup_mode = "Disabled"

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.firehose.name
      log_stream_name = aws_cloudwatch_log_stream.firehose_s3.name
    }
  }

  tags = local.common_tags
}

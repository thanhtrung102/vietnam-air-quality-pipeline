# ── Lambda: OpenAQ Kinesis Producer ───────────────────────────────────────────
#
# Prerequisite: run `bash lambda/build.sh` from the repo root before
# `terraform apply` to create lambda/openaq_producer.zip.
#
# The Lambda execution role (openaq_pipeline_role) is declared in main.tf
# and already trusts lambda.amazonaws.com.

locals {
  lambda_zip = "${path.module}/../lambda/openaq_producer.zip"
}

# CloudWatch log group — created before the function so logs are retained
# even if the function is destroyed and recreated.
resource "aws_cloudwatch_log_group" "lambda_producer" {
  name              = "/aws/lambda/openaq_producer"
  retention_in_days = 14

  tags = local.common_tags
}

resource "aws_lambda_function" "producer" {
  function_name    = "openaq_producer"
  description      = "Fetch latest OpenAQ VN measurements and publish to Kinesis — triggered by EventBridge Scheduler every 2 hours"
  filename         = local.lambda_zip
  source_code_hash = filebase64sha256(local.lambda_zip)
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  timeout          = 300  # 5 min — 20 stations × ~1 s API round-trip + Kinesis write
  memory_size      = 256  # MB

  role = aws_iam_role.pipeline.arn

  environment {
    variables = {
      OPENAQ_API_KEY      = var.openaq_api_key
      KINESIS_STREAM_NAME = aws_kinesis_stream.openaq.name
      # AWS_REGION is injected automatically by the Lambda runtime
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda_producer]

  tags = local.common_tags
}

# ── EventBridge Scheduler ─────────────────────────────────────────────────────
# Invokes the producer every 2 hours.  A dedicated scheduler role is used
# (separate from the Lambda execution role) so least-privilege is preserved.

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
    sid     = "InvokeProducerLambda"
    effect  = "Allow"
    actions = ["lambda:InvokeFunction"]

    resources = [aws_lambda_function.producer.arn]
  }
}

resource "aws_iam_role_policy" "scheduler_invoke" {
  name   = "openaq_scheduler_invoke_policy"
  role   = aws_iam_role.scheduler.id
  policy = data.aws_iam_policy_document.scheduler_invoke.json
}

resource "aws_scheduler_schedule" "producer_every_2h" {
  name                         = "openaq-producer-every-2h"
  description                  = "Trigger OpenAQ Kinesis producer every 2 hours"
  schedule_expression          = "rate(2 hours)"
  schedule_expression_timezone = "UTC"
  state                        = "ENABLED"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.producer.arn
    role_arn = aws_iam_role.scheduler.arn
  }
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "lambda_producer_arn" {
  description = "ARN of the openaq_producer Lambda function"
  value       = aws_lambda_function.producer.arn
}

output "scheduler_schedule_arn" {
  description = "ARN of the EventBridge Scheduler schedule"
  value       = aws_scheduler_schedule.producer_every_2h.arn
}

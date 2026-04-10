# ── QuickSight IAM & User (Phase 1) ──────────────────────────────────────────
#
# Prerequisites (one-time, manual, cannot be automated via Terraform):
#   1. Subscribe to QuickSight Enterprise in ap-southeast-1:
#      AWS Console → QuickSight → Sign up for QuickSight
#   2. Then run: terraform apply -target=aws_iam_role.quicksight_service ...
#
# Resources managed here:
#   - aws_iam_role.quicksight_service         — assumed by the QuickSight service
#   - aws_iam_role_policy.quicksight_service  — Athena + Glue + S3 access
#   - aws_quicksight_user.admin               — Author account for dashboard ownership

# ── Service role ──────────────────────────────────────────────────────────────

resource "aws_iam_role" "quicksight_service" {
  name = "QuickSightServiceRole-openaq"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowQuickSightAssume"
      Effect    = "Allow"
      Principal = { Service = "quicksight.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "quicksight_service" {
  name = "quicksight-openaq-access"
  role = aws_iam_role.quicksight_service.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Athena — execute queries in the openaq workgroup
        Sid    = "AthenaQuery"
        Effect = "Allow"
        Action = [
          "athena:BatchGetQueryExecution",
          "athena:GetQueryExecution",
          "athena:GetQueryResults",
          "athena:GetQueryResultsStream",
          "athena:GetWorkGroup",
          "athena:ListQueryExecutions",
          "athena:StartQueryExecution",
          "athena:StopQueryExecution",
        ]
        Resource = [
          "arn:aws:athena:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:workgroup/openaq_workgroup",
        ]
      },
      {
        # Glue catalog — read databases and tables (no write needed for QuickSight)
        Sid    = "GlueCatalogRead"
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:GetDatabases",
          "glue:GetTable",
          "glue:GetTables",
          "glue:GetPartition",
          "glue:GetPartitions",
          "glue:BatchGetPartition",
        ]
        Resource = [
          "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:catalog",
          "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:database/openaq_raw",
          "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:database/openaq_mart",
          "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/openaq_raw/*",
          "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/openaq_mart/*",
        ]
      },
      {
        # S3 — read processed mart Parquet and Athena results
        Sid    = "S3Read"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
        ]
        Resource = [
          aws_s3_bucket.main.arn,
          "${aws_s3_bucket.main.arn}/*",
        ]
      },
      {
        # S3 — QuickSight writes Athena query results to a dedicated staging prefix
        Sid    = "S3WriteQuickSightStaging"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:AbortMultipartUpload",
        ]
        Resource = "${aws_s3_bucket.main.arn}/quicksight-staging/*"
      },
    ]
  })
}

# ── QuickSight Author user ARN ────────────────────────────────────────────────
#
# QuickSight was subscribed manually before Terraform was introduced. The
# terraform-admin IAM user was automatically registered as QuickSight user
# "terraform-admin" in namespace "default".
#
# aws_quicksight_user does NOT support import, so we cannot bring the existing
# user into Terraform state. Instead we derive the ARN deterministically from
# the known account ID and QuickSight username, and expose it as a local so
# that downstream resources (datasets, dashboard) can reference it.
#
# To register a NEW QuickSight user from scratch (e.g. on a fresh account),
# uncomment the resource block below and remove the local:
#
# resource "aws_quicksight_user" "admin" {
#   aws_account_id = data.aws_caller_identity.current.account_id
#   email          = var.quicksight_admin_email
#   identity_type  = "IAM"
#   user_role      = "AUTHOR"
#   namespace      = "default"
#   iam_arn        = data.aws_caller_identity.current.arn
# }

locals {
  # QuickSight user ARN for the terraform-admin IAM user registered at
  # account subscription time. Format:
  #   arn:aws:quicksight:<region>:<account_id>:user/<namespace>/<iam_username>
  quicksight_user_arn = "arn:aws:quicksight:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:user/default/terraform-admin"
}

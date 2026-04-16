# ── QuickSight Data Source: Athena (Phase 2.1) ────────────────────────────────
#
# One data source wires QuickSight → Athena workgroup.
# All nine datasets share this single data source.
#
# Depends on:
#   - aws_athena_workgroup.openaq     (main.tf)
#   - local.quicksight_user_arn       (quicksight_iam.tf)
#   - aws_iam_role.quicksight_service (quicksight_iam.tf)

resource "aws_quicksight_data_source" "athena" {
  aws_account_id = data.aws_caller_identity.current.account_id
  data_source_id = "openaq-athena"
  name           = "OpenAQ Athena"
  type           = "ATHENA"

  parameters {
    athena {
      work_group = aws_athena_workgroup.openaq.name
    }
  }

  ssl_properties {
    disable_ssl = false
  }

  # Grant the pre-existing QuickSight admin (terraform-admin IAM user) full
  # ownership over this data source so it can create/update datasets.
  permission {
    actions = [
      "quicksight:DescribeDataSource",
      "quicksight:DescribeDataSourcePermissions",
      "quicksight:PassDataSource",
      "quicksight:UpdateDataSource",
      "quicksight:DeleteDataSource",
      "quicksight:UpdateDataSourcePermissions",
    ]
    principal = local.quicksight_user_arn
  }

  tags = local.common_tags
}

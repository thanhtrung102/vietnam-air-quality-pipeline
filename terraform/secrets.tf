# ── Secrets Manager: OPENAQ_API_KEY (Gap 2 — IoT Lens) ───────────────────────
#
# Stores the OpenAQ v3 API key in Secrets Manager instead of as a plaintext
# Lambda environment variable. The streaming Lambda reads this secret at cold-
# start via _get_api_key() and caches the value for the container lifetime.
#
# Recovery window = 0 enables immediate deletion on `terraform destroy` without
# the default 7–30 day retention. Appropriate for a dev/demo pipeline; set to
# a non-zero value (7–30) in production.
#
# Post-deploy: inject the real key with:
#   aws secretsmanager put-secret-value \
#       --secret-id openaq/api_key \
#       --secret-string "YOUR_REAL_KEY"
#
# The placeholder string below is committed only to satisfy the required_version
# constraint on aws_secretsmanager_secret_version. The Lambda handler falls back
# to OPENAQ_API_KEY env var if the secret value equals "REPLACE_ME".

resource "aws_secretsmanager_secret" "openaq_api_key" {
  name                    = "openaq/api_key"
  description             = "OpenAQ v3 API key for openaq_streaming_producer Lambda"
  recovery_window_in_days = 0   # immediate delete on destroy; change to 7+ in production

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "openaq_api_key" {
  secret_id     = aws_secretsmanager_secret.openaq_api_key.id
  secret_string = "REPLACE_ME"

  # Prevent Terraform from re-applying this resource after the real key is set
  # via CLI. The lifecycle block ignores changes to secret_string post-deploy.
  lifecycle {
    ignore_changes = [secret_string]
  }
}
# ── Secrets Manager: OPENAQ_API_KEY (Gap 2 — IoT Lens) ───────────────────────
#
# Stores the OpenAQ v3 API key in Secrets Manager instead of as a plaintext
# Lambda environment variable. The streaming Lambda reads this secret at cold-
# start via _get_api_key() and caches the value for the container lifetime.
#
# recovery_window_in_days is set to 7 below. Use
# `--force-delete-without-recovery` on the CLI for an immediate teardown in
# dev/demo; raise toward 30 in production.
#
# Post-deploy (REQUIRED — the streaming Lambda reads the key only from here):
#   aws secretsmanager put-secret-value \
#       --secret-id openaq/api_key \
#       --secret-string "YOUR_REAL_KEY"
#
# The placeholder string below is committed only to satisfy the required
# initial-version constraint on aws_secretsmanager_secret_version. Until the
# real key is injected, the streaming handler logs a missing-key error (the
# plaintext OPENAQ_API_KEY env-var fallback has been removed).

resource "aws_secretsmanager_secret" "openaq_api_key" {
  name                    = "openaq/api_key"
  description             = "OpenAQ v3 API key for openaq_streaming_producer Lambda"
  recovery_window_in_days = 7 # 7-day recovery window; use --force-delete-without-recovery for immediate teardown

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
#!/usr/bin/env bash
# postdeploy.sh — run once after every `terraform apply`
#
# Automates the one manual step that Terraform cannot perform directly:
#   Inject the real OpenAQ API key into Secrets Manager.
#
# Usage (from the terraform/ directory):
#   bash postdeploy.sh
#
# Requirements:
#   - AWS CLI installed and authenticated with secretsmanager:GetSecretValue
#     and secretsmanager:PutSecretValue on the openaq/api_key secret
#   - terraform output must be available (i.e. terraform apply has completed)

set -euo pipefail

SECRET_NAME=$(terraform output -raw openaq_api_key_secret_name)
REGION=$(terraform output -raw aws_region)

echo "── OpenAQ API key secret check ──────────────────────────────"
echo "Secret : ${SECRET_NAME}"
echo "Region : ${REGION}"
echo ""

CURRENT=$(aws secretsmanager get-secret-value \
  --secret-id "${SECRET_NAME}" \
  --region "${REGION}" \
  --query SecretString \
  --output text 2>/dev/null || echo "REPLACE_ME")

if [ "${CURRENT}" = "REPLACE_ME" ]; then
  echo "Secret is still placeholder. Enter the real OpenAQ v3 API key"
  echo "(input is hidden):"
  read -rs API_KEY
  echo ""

  if [ -z "${API_KEY}" ]; then
    echo "ERROR: empty key provided — aborting." >&2
    exit 1
  fi

  aws secretsmanager put-secret-value \
    --secret-id "${SECRET_NAME}" \
    --secret-string "${API_KEY}" \
    --region "${REGION}"

  echo "Secret updated. Streaming Lambda will use Secrets Manager on next cold start."
else
  echo "Secret already set — skipping injection."
fi

echo ""
echo "── Post-deploy complete ─────────────────────────────────────"

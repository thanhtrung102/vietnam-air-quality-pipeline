#!/usr/bin/env bash
# lambda/build.sh — Build all Lambda deployment zips.
#
# Usage (from repo root):
#   bash lambda/build.sh
#
# Outputs (gitignored):
#   lambda/batch_sync.zip          — referenced by terraform var.lambda_batch_zip_path
#   lambda/streaming.zip           — referenced by terraform var.lambda_streaming_zip_path
#   lambda/aqi_api.zip             — referenced by terraform var.lambda_aqi_api_zip_path
#   lambda/completeness_check.zip  — referenced by terraform var.lambda_completeness_zip_path
#
# Run before every `terraform apply` that touches any aws_lambda_function.
# Terraform uses each zip's SHA-256 hash to detect changes and force updates.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAMBDA_DIR="$REPO_ROOT/lambda"
PACKAGE_DIR="$LAMBDA_DIR/package"

# Prefer the project venv pip; fall back to system pip
VENV_PIP="$REPO_ROOT/.venv/Scripts/pip"
PIP="${VENV_PIP:-pip}"

# ── Helpers ────────────────────────────────────────────────────────────────────

zip_dir() {
  local src="$1"
  local out="$2"
  python3 - "$src" "$out" <<'PYEOF'
import sys, zipfile, pathlib

src = pathlib.Path(sys.argv[1])
out = pathlib.Path(sys.argv[2])

with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
    for path in src.rglob("*"):
        if path.is_dir():
            continue
        parts = path.parts
        if any(p.endswith(".dist-info") or p in ("__pycache__",) for p in parts):
            continue
        if path.suffix == ".pyc":
            continue
        zf.write(path, path.relative_to(src))

print(f"  wrote {out}  ({out.stat().st_size // 1024} KB)")
PYEOF
}

# ── 1. batch_sync.zip ─────────────────────────────────────────────────────────
# boto3 is provided by the Lambda runtime — no extra deps needed.

echo "==> batch_sync.zip"
rm -rf "$PACKAGE_DIR" && mkdir -p "$PACKAGE_DIR"
cp "$LAMBDA_DIR/batch_sync/handler.py" "$PACKAGE_DIR/"
zip_dir "$PACKAGE_DIR" "$LAMBDA_DIR/batch_sync.zip"

# ── 2. streaming.zip ──────────────────────────────────────────────────────────
# Bundles kinesis_producer.py + requests (boto3 from runtime).

echo "==> streaming.zip"
rm -rf "$PACKAGE_DIR" && mkdir -p "$PACKAGE_DIR"
"$PIP" install \
  requests==2.32.5 \
  -t "$PACKAGE_DIR/" \
  --quiet
cp "$LAMBDA_DIR/streaming/handler.py"          "$PACKAGE_DIR/"
cp "$LAMBDA_DIR/streaming/kinesis_producer.py" "$PACKAGE_DIR/"
zip_dir "$PACKAGE_DIR" "$LAMBDA_DIR/streaming.zip"

# ── 3. aqi_api.zip ────────────────────────────────────────────────────────────
# boto3 is provided by the Lambda runtime — no extra deps needed.

echo "==> aqi_api.zip"
rm -rf "$PACKAGE_DIR" && mkdir -p "$PACKAGE_DIR"
cp "$LAMBDA_DIR/aqi_api/handler.py" "$PACKAGE_DIR/"
zip_dir "$PACKAGE_DIR" "$LAMBDA_DIR/aqi_api.zip"

# ── 4. completeness_check.zip ────────────────────────────────────────────────
# boto3 is provided by the Lambda runtime — no extra deps needed.

echo "==> completeness_check.zip"
rm -rf "$PACKAGE_DIR" && mkdir -p "$PACKAGE_DIR"
cp "$LAMBDA_DIR/completeness_check/handler.py" "$PACKAGE_DIR/"
zip_dir "$PACKAGE_DIR" "$LAMBDA_DIR/completeness_check.zip"

# ── Cleanup ───────────────────────────────────────────────────────────────────

rm -rf "$PACKAGE_DIR"
echo "==> Done. Run 'terraform plan' from terraform/ to verify hashes."

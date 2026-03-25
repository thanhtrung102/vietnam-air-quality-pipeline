#!/usr/bin/env bash
# lambda/build.sh — Package openaq_producer Lambda function
#
# Usage (from repo root):
#   bash lambda/build.sh
#
# Output: lambda/openaq_producer.zip  (gitignored)
#
# Run this before every `terraform apply` that touches aws_lambda_function.producer.
# Terraform uses the zip's SHA-256 hash to detect changes and force Lambda updates.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAMBDA_DIR="$REPO_ROOT/lambda"
PACKAGE_DIR="$LAMBDA_DIR/package"
OUTPUT_ZIP="$LAMBDA_DIR/openaq_producer.zip"

# Prefer the project venv pip; fall back to system pip
VENV_PIP="$REPO_ROOT/.venv/Scripts/pip"
PIP="${VENV_PIP:-pip}"

echo "==> Cleaning package directory..."
rm -rf "$PACKAGE_DIR"
mkdir -p "$PACKAGE_DIR"

echo "==> Installing Python dependencies into package/..."
"$PIP" install \
  -r "$LAMBDA_DIR/streaming/requirements.txt" \
  -t "$PACKAGE_DIR/" \
  --quiet

echo "==> Copying Lambda source files..."
cp "$LAMBDA_DIR/streaming/handler.py"                      "$PACKAGE_DIR/"
cp "$REPO_ROOT/ingestion/streaming/kinesis_producer.py"    "$PACKAGE_DIR/"

echo "==> Creating zip archive (using Python zipfile)..."
"$PIP" show pip > /dev/null  # confirm venv is active
PYTHON="$(dirname "$PIP")/python"
"$PYTHON" - "$PACKAGE_DIR" "$OUTPUT_ZIP" <<'PYEOF'
import sys, zipfile, os, pathlib

src = pathlib.Path(sys.argv[1])
out = pathlib.Path(sys.argv[2])

skip_exts = {".pyc"}
skip_dirs = {"__pycache__", "*.dist-info"}

with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
    for path in src.rglob("*"):
        if path.is_dir():
            continue
        if path.suffix in skip_exts:
            continue
        parts = path.parts
        if any(p.endswith(".dist-info") or p == "__pycache__" for p in parts):
            continue
        arcname = path.relative_to(src)
        zf.write(path, arcname)

print(f"  wrote {out}")
PYEOF

SIZE="$(du -sh "$OUTPUT_ZIP" | cut -f1)"
echo "==> Done: $SIZE  →  $OUTPUT_ZIP"

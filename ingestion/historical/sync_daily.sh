#!/usr/bin/env bash
# sync_daily.sh — Incremental sync for the current month across all Vietnamese stations.
#
# Designed to run daily (e.g. via cron or Kestra). Syncs only:
#   s3://openaq-data-archive/records/csv.gz/locationid={id}/year={YYYY}/month={MM}/
# for the current year and month, making it fast and cheap — aws s3 sync is
# idempotent so re-running when all files already exist produces no copies.
#
# Usage:
#   source ../../.env && bash sync_daily.sh
#   bash sync_daily.sh --dry-run           # print commands, no sync
#   bash sync_daily.sh --year 2025 --month 11   # override date (backfill use)

set -euo pipefail

# ── Argument parsing ──────────────────────────────────────────────────────────

DRY_RUN=false
OVERRIDE_YEAR=""
OVERRIDE_MONTH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true;             shift ;;
    --year)    OVERRIDE_YEAR="$2";       shift 2 ;;
    --month)   OVERRIDE_MONTH="$2";      shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# ── Resolve target year / month ───────────────────────────────────────────────

YEAR="${OVERRIDE_YEAR:-$(date +%Y)}"
MONTH="${OVERRIDE_MONTH:-$(date +%m)}"   # zero-padded: 01..12

# ── Validation ────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATION_FILE="${SCRIPT_DIR}/station_ids.txt"

if [[ -z "${S3_BUCKET_NAME:-}" ]]; then
  echo "ERROR: S3_BUCKET_NAME environment variable is not set." >&2
  echo "       Run: source .env && bash sync_daily.sh" >&2
  exit 1
fi

if [[ ! -f "$STATION_FILE" ]]; then
  echo "ERROR: station_ids.txt not found at ${STATION_FILE}" >&2
  exit 1
fi

mapfile -t STATION_IDS < <(sed 's/#.*//' "$STATION_FILE" | tr -d ' \t' | grep -v '^$')

if [[ ${#STATION_IDS[@]} -eq 0 ]]; then
  echo "ERROR: station_ids.txt contains no valid station IDs." >&2
  exit 1
fi

# ── Summary ───────────────────────────────────────────────────────────────────

echo "=================================================="
echo " OpenAQ daily incremental sync"
echo "=================================================="
echo " Bucket    : s3://${S3_BUCKET_NAME}"
echo " Period    : ${YEAR}-${MONTH}"
echo " Stations  : ${#STATION_IDS[@]}"
echo " Dry-run   : ${DRY_RUN}"
echo "=================================================="

# ── Sync loop ─────────────────────────────────────────────────────────────────

SUCCESS=0
FAILED=0
FAILED_LIST=()

for id in "${STATION_IDS[@]}"; do

  src="s3://openaq-data-archive/records/csv.gz/locationid=${id}/year=${YEAR}/month=${MONTH}/"
  dst="s3://${S3_BUCKET_NAME}/raw/batch/locationid=${id}/year=${YEAR}/month=${MONTH}/"

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] aws s3 sync ${src} ${dst} --request-payer requester --only-show-errors"
    continue
  fi

  if aws s3 sync "${src}" "${dst}" \
      --request-payer requester \
      --only-show-errors; then
    SUCCESS=$((SUCCESS + 1))
  else
    echo "  WARNING: sync failed for locationid=${id} year=${YEAR} month=${MONTH}" >&2
    FAILED=$((FAILED + 1))
    FAILED_LIST+=("locationid=${id}/year=${YEAR}/month=${MONTH}")
  fi

done

# ── Report ────────────────────────────────────────────────────────────────────

echo ""
echo "=================================================="
if [[ "$DRY_RUN" == "true" ]]; then
  echo " Dry-run complete — ${#STATION_IDS[@]} sync(s) would run for ${YEAR}-${MONTH}"
else
  echo " Done — success=${SUCCESS}  failed=${FAILED}  period=${YEAR}-${MONTH}"
  if [[ ${#FAILED_LIST[@]} -gt 0 ]]; then
    echo " Failed paths:"
    for p in "${FAILED_LIST[@]}"; do
      echo "   ${p}"
    done
  fi
fi
echo "=================================================="

[[ $FAILED -eq 0 ]]

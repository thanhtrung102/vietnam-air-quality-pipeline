#!/usr/bin/env bash
# sync_historical.sh — Sync OpenAQ archive data for Vietnamese stations to S3
#
# For each station ID in station_ids.txt and each year 2023-2026, runs:
#   aws s3 sync s3://openaq-data-archive/records/csv.gz/locationid={id}/year={year}/
#              s3://${S3_BUCKET_NAME}/raw/batch/locationid={id}/year={year}/
#
# Usage:
#   source ../../.env && bash sync_historical.sh
#   bash sync_historical.sh --dry-run          # print commands, no sync
#   bash sync_historical.sh --year 2024        # single year only
#   bash sync_historical.sh --station 7441     # single station only

set -euo pipefail

# ── Argument parsing ──────────────────────────────────────────────────────────

DRY_RUN=false
FILTER_YEAR=""
FILTER_STATION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)       DRY_RUN=true;          shift ;;
    --year)          FILTER_YEAR="$2";      shift 2 ;;
    --station)       FILTER_STATION="$2";   shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# ── Validation ────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATION_FILE="${SCRIPT_DIR}/station_ids.txt"

if [[ -z "${S3_BUCKET_NAME:-}" ]]; then
  echo "ERROR: S3_BUCKET_NAME environment variable is not set." >&2
  echo "       Run: source .env && bash sync_historical.sh" >&2
  exit 1
fi

if [[ ! -f "$STATION_FILE" ]]; then
  echo "ERROR: station_ids.txt not found at ${STATION_FILE}" >&2
  exit 1
fi

# Read station IDs: strip comments (#...) and blank lines, trim whitespace
mapfile -t STATION_IDS < <(sed 's/#.*//' "$STATION_FILE" | tr -d ' \t' | grep -v '^$')

if [[ ${#STATION_IDS[@]} -eq 0 ]]; then
  echo "ERROR: station_ids.txt contains no valid station IDs (all lines are comments or blank)." >&2
  exit 1
fi

YEARS=(2023 2024 2025 2026)

# ── Summary ───────────────────────────────────────────────────────────────────

echo "=================================================="
echo " OpenAQ historical sync"
echo "=================================================="
echo " Bucket    : s3://${S3_BUCKET_NAME}"
echo " Stations  : ${#STATION_IDS[@]}"
echo " Years     : ${YEARS[*]}"
echo " Filter    : year=${FILTER_YEAR:-all}  station=${FILTER_STATION:-all}"
echo " Dry-run   : ${DRY_RUN}"
echo "=================================================="

# ── Sync loop ─────────────────────────────────────────────────────────────────

SUCCESS=0
SKIPPED=0
FAILED=0
FAILED_LIST=()

for id in "${STATION_IDS[@]}"; do

  # Apply --station filter if set
  if [[ -n "$FILTER_STATION" && "$id" != "$FILTER_STATION" ]]; then
    continue
  fi

  for year in "${YEARS[@]}"; do

    # Apply --year filter if set
    if [[ -n "$FILTER_YEAR" && "$year" != "$FILTER_YEAR" ]]; then
      continue
    fi

    src="s3://openaq-data-archive/records/csv.gz/locationid=${id}/year=${year}/"
    dst="s3://${S3_BUCKET_NAME}/raw/batch/locationid=${id}/year=${year}/"

    if [[ "$DRY_RUN" == "true" ]]; then
      echo "[dry-run] aws s3 sync ${src} ${dst} --no-sign-request --only-show-errors"
      SKIPPED=$((SKIPPED + 1))
      continue
    fi

    echo "syncing  locationid=${id}  year=${year} ..."
    if aws s3 sync "${src}" "${dst}" \
        --no-sign-request \
        --only-show-errors; then
      SUCCESS=$((SUCCESS + 1))
    else
      echo "  WARNING: sync failed for locationid=${id} year=${year}" >&2
      FAILED=$((FAILED + 1))
      FAILED_LIST+=("locationid=${id}/year=${year}")
    fi

  done
done

# ── Report ────────────────────────────────────────────────────────────────────

echo ""
echo "=================================================="
if [[ "$DRY_RUN" == "true" ]]; then
  echo " Dry-run complete — ${SKIPPED} sync(s) would run"
else
  echo " Done — success=${SUCCESS}  failed=${FAILED}"
  if [[ ${#FAILED_LIST[@]} -gt 0 ]]; then
    echo " Failed paths:"
    for p in "${FAILED_LIST[@]}"; do
      echo "   ${p}"
    done
  fi
fi
echo "=================================================="

[[ $FAILED -eq 0 ]]   # exit 1 if any sync failed

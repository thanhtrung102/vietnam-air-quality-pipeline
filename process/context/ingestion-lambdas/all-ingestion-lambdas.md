# Ingestion Lambdas — Context Group

Last updated: 2026-05-31. Router for the three ingest paths feeding the raw S3 zone.
Parent: `process/context/all-context.md`.

## Scope

batch_sync, streaming_producer, weather_ingest; Kinesis Data Stream + Firehose; Secrets Manager;
the OpenAQ (archive + REST v3) and Open-Meteo ERA5 source contracts.

## Read when

Touching any ingest Lambda, the Kinesis/Firehose path, the OpenAQ/Open-Meteo source contract, the
API-key secret, or the raw S3 layout.

## Quick facts (canonical owners linked — do not duplicate)

- **3 live ingest Lambdas** (verified 2026-05-31):
  - `openaq_batch_sync` — 512 MB, 900 s, daily 01:00 UTC. OpenAQ S3 archive (requester-pays, us-east-1)
    → `raw/batch/`. boto3 ETag-skip (idempotent), ThreadPool(8). DLQ `openaq_batch_sync_dlq`.
    **Copies archive objects via in-memory bytes, not raw stream** (fixed `MissingContentLength`
    data-loss bug — see commit f06614d / ARCHITECTURE-EVALUATION).
  - `openaq_streaming_producer` — 256 MB, 120 s, every 30 min. OpenAQ REST v3 (key from Secrets
    Manager, cached at cold start) → Kinesis `openaq_stream` → Firehose → `raw/stream/`. Validates
    `-999` sentinel. DLQ `openaq_streaming_dlq`.
  - `openaq_weather_ingest` — 256 MB, 300 s, daily 02:00 UTC. Open-Meteo ERA5 prev-day hourly for 21
    coords → `raw/weather/{location_id}/{yyyy}/{MM}/{dd}/weather.ndjson`.
- **Secret-only auth:** streaming env = `{KINESIS_STREAM_NAME, OPENAQ_SECRET_NAME, STATION_IDS}` — no
  plaintext key. Secret `openaq/api_key` is live and read successfully (LastAccessed today).
- **Kinesis:** on-demand + KMS SSE (`alias/aws/kinesis`).
- **OpenAQ source contract:** archive file `location-{id}-{YYYYMMDD}.csv.gz`; 9 columns; `datetime` is
  ISO-8601 with `+07:00` offset (`from_iso8601_timestamp`); `-999.0` = missing.

## Source docs

- Design rationale: `docs/PIPELINE-REPORT.md` "Ingestion"
- Data flow per stage: `docs/DATA-LIFECYCLE.md` §1
- Build-from-scratch: `docs/workshop/5.4-ingestion.md` (legacy numbers — see drift note in root)
- Facts/roster/source contract: `CLAUDE.md` (OpenAQ section)

## Source code

`lambda/batch_sync/`, `lambda/streaming/` (`handler.py` + `kinesis_producer.py`),
`lambda/weather_ingest/`, `lambda/shared/athena_utils.py`, `lambda/tests/`,
`ingestion/historical/sync_historical.sh`, `terraform/{lambda,kinesis,secrets}.tf`.

## Known issues / drift surfaces

- **Station roster duplicated** across `ingestion/historical/station_ids.txt`, weather_ingest hardcoded
  coords, batch_sync default list — canonical is `transform/seeds/vn_stations.csv` (partially
  de-duplicated via `csvdecode` in Terraform). Treat the seed as the one source of truth.
- `data_age_days: 994` from completeness_check measures `raw/stream` last date (2025-04-09), not the
  mart — not a contradiction with the "~10 days behind" mart narrative.

## Update triggers

New ingest source, schedule/memory change, secret rotation, Kinesis/Firehose reconfig, source-schema
change. After any change: verify live (`aws lambda get-function-configuration`) before updating facts.

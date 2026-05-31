-- Freshness gate: detect a stalled batch_sync (no new source data reaching the marts).
--
-- Replaces `dbt source freshness`, which is unreliable on dbt-athena: the adapter
-- computes freshness from Glue table metadata (`last_modified`) returned as a string,
-- so it errors on every source (https://github.com/dbt-labs/dbt-athena/issues/631).
--
-- Why this checks the MART, not the raw `batch` source: `mart_daily_aqi` is Parquet,
-- partitioned by `measurement_date`, and built directly from the batch source via
-- stg_measurements — so its newest `measurement_date` advances iff fresh source data
-- arrives, and a `max(measurement_date)` prunes to a single partition's metadata
-- (near-zero scan). Querying the mart (not the raw CSV) also keeps the result a `date`,
-- which is storable by `--store-failures` (a `timestamp with time zone` from
-- `from_iso8601_timestamp` on the raw source is NOT — dbt-athena CTAS rejects it). A
-- stalled source still surfaces: if batch_sync stops, the mart stops gaining new days
-- even on a green rebuild.
--   (Note: scanning the raw `batch` source directly is *not* prohibitively expensive at
--    today's volume — a live `max(datetime)` probe scanned only ~10 MB, 2026-05-31 —
--    but the mart-query approach is still preferred: it's date-typed for --store-failures
--    and stays cheap as the raw history grows.)
--
-- Threshold = 21 days, matching the deployed `DaysSinceLastNewMart` CloudWatch alarm
-- (the canonical freshness SLA) so the two cannot disagree. The OpenAQ archive lags
-- ~72 h and can run up to ~10 days behind wall-clock under *normal* healthy operation
-- (see docs/PIPELINE-REPORT.md §6), so a tighter threshold (an earlier version used 3
-- days) false-fires on normal lag and reintroduces the constant-WARN masking that Lane 4
-- explicitly warns against. >21 days behind signals a genuinely stalled sync. Runs in
-- the non-blocking post_build `dbt test` step (surfaces in CloudWatch without failing the
-- build). Empty result = pass.

select max(measurement_date) as newest_mart_day
from {{ ref('mart_daily_aqi') }}
having max(measurement_date) < date_add('day', -21, current_date)

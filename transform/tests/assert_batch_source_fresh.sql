-- Freshness gate: detect a stalled batch_sync (no new source data reaching the marts).
--
-- Replaces `dbt source freshness`, which is unreliable on dbt-athena: the adapter
-- computes freshness from Glue table metadata (`last_modified`) returned as a string,
-- so it errors on every source (https://github.com/dbt-labs/dbt-athena/issues/631).
--
-- IMPORTANT — why this checks the MART, not the raw `batch` source: the raw batch
-- table is a partition-projected external CSV (~1.4M+ rows). A `max(datetime)` over it
-- has no partition pruning and scans the full history, blowing the workgroup's 10 GB
-- scan cap (an earlier source-scanning version of this test ERRORed after ~145s for
-- exactly that reason). `mart_daily_aqi` is Parquet, partitioned by `measurement_date`,
-- and built directly from the batch source via stg_measurements — so its newest
-- `measurement_date` advances iff fresh source data arrives. Checking it prunes to a
-- single partition's metadata (near-zero scan) and still catches a stalled source:
-- if batch_sync stops, the mart stops gaining new days even on a green rebuild.
--
-- Fails (returns a row) when the newest mart day is older than 3 days. OpenAQ's
-- archive lags ~1–2 days, so the newest measurement_date is normally yesterday or the
-- day before; >3 days signals a stalled sync. Runs in the non-blocking post_build
-- `dbt test` step (surfaces in CloudWatch without failing the build) and is backed by
-- the deployed DaysSinceLastNewMart alarm. Empty result = pass.

select max(measurement_date) as newest_mart_day
from {{ ref('mart_daily_aqi') }}
having max(measurement_date) < date_add('day', -3, current_date)

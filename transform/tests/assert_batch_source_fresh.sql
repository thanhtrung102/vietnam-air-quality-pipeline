-- Source-freshness gate for the `batch` measurements source.
--
-- Replaces `dbt source freshness`, which is unreliable on dbt-athena: the adapter
-- computes freshness from Glue table metadata (`last_modified`) and returns it as a
-- string, so it errors on every source regardless of actual freshness
-- (https://github.com/dbt-labs/dbt-athena/issues/631). This query-based check runs
-- fine on Athena.
--
-- Fails (returns a row) when the newest batch measurement is older than 49h — the
-- source's former `error_after` SLA. The daily batch_sync (01:00 UTC) plus OpenAQ
-- archive lag means the freshest row is normally < 48h old; crossing 49h signals a
-- stalled sync. Runs in the non-blocking post_build `dbt test` step, so a breach
-- surfaces in CloudWatch without failing the nightly build (mirrors the existing
-- test posture). `datetime` is an ISO-8601 string with a +07:00 offset;
-- from_iso8601_timestamp parses it to a tz-aware instant, compared against the
-- session-zone current_timestamp by instant. Empty result = pass.

select max(from_iso8601_timestamp(datetime)) as newest_measurement
from {{ source('openaq_raw', 'batch') }}
having max(from_iso8601_timestamp(datetime)) < current_timestamp - interval '49' hour

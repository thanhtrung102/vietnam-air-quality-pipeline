-- Freshness gate: detect stalled weather_ingest (no new ERA5 weather reaching the marts).
--
-- Mirrors tests/assert_batch_source_fresh.sql (see that file for why a query-based
-- singular test is used instead of `dbt source freshness`, which errors on dbt-athena
-- — https://github.com/dbt-labs/dbt-athena/issues/631). Queries the consumer mart
-- `mart_daily_weather` (Parquet, partitioned by `measurement_date`), so the result is a
-- `date` (storable by --store-failures) and the scan prunes to a single partition's
-- metadata. mart_daily_weather is built from the weather source via
-- int_weather_enriched, so its newest day advances iff fresh weather data arrives, and
-- it feeds mart_aq_weather_daily + mart_lagged_features (the forecast feature mart).
--
-- Threshold = 7 days. Open-Meteo serves ERA5T with a shorter publication lag than the
-- OpenAQ archive (live probe 2026-05-31: weather mart only 1 day behind wall-clock vs
-- the AQI mart's 3), so weather warrants a tighter SLA than batch's 21 days — but still
-- loose enough to absorb the variable ERA5 reanalysis lag without false-firing. There is
-- no dedicated CloudWatch alarm for weather freshness (unlike DaysSinceLastNewMart for
-- the AQI mart), so this test is the freshness signal for the weather path. Runs in the
-- non-blocking post_build `dbt test` step (surfaces in CloudWatch without failing the
-- build). Empty result = pass.

select max(measurement_date) as newest_weather_day
from {{ ref('mart_daily_weather') }}
having max(measurement_date) < date_add('day', -7, current_date)

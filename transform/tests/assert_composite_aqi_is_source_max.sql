-- Invariant: mart_daily_aqi.composite_aqi MUST equal the maximum per-pollutant
-- aqi_value from mart_daily_air_quality for the same station-day (US EPA composite
-- AQI = worst individual pollutant), over non-outlier stations with a real AQI.
-- Guards the composite/join-back logic in mart_daily_aqi against drift or row
-- duplication/loss. Returns offending rows; empty = pass.

with expected as (
    select
        measurement_date,
        location_id,
        max(aqi_value) as expected_composite
    from {{ ref('mart_daily_air_quality') }}
    where aqi_value is not null
      and is_outlier_station = 0
    group by measurement_date, location_id
)

select
    m.measurement_date,
    m.location_id,
    m.composite_aqi,
    e.expected_composite
from {{ ref('mart_daily_aqi') }} m
join expected e
    on  m.measurement_date = e.measurement_date
    and m.location_id      = e.location_id
where m.composite_aqi <> e.expected_composite

-- Invariant: the health_category label MUST match the band implied by the numeric
-- composite_aqi (US EPA AQI breakpoints). Independently re-derives the expected
-- label from composite_aqi and flags any mismatch — catches breakpoint/category
-- drift or a max_by tie-break that selects a category inconsistent with the value.
-- Returns offending rows; empty = pass.

select
    measurement_date,
    location_id,
    composite_aqi,
    health_category
from {{ ref('mart_daily_aqi') }}
where health_category <> case
        when composite_aqi <=  50 then 'Good'
        when composite_aqi <= 100 then 'Moderate'
        when composite_aqi <= 150 then 'Unhealthy for Sensitive Groups'
        when composite_aqi <= 200 then 'Unhealthy'
        when composite_aqi <= 300 then 'Very Unhealthy'
        else                           'Hazardous'
    end

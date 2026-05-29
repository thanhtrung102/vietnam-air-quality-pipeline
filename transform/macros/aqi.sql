{#
    AQI macros — single source of truth for the US EPA 2024 AQI breakpoint table.

    The PM2.5 24-hour breakpoints were updated by the US EPA in May 2024 (annual
    NAAQS lowered from 12.0 to 9.0 µg/m³). PM10 24-hour breakpoints are unchanged.

    These macros centralise the breakpoint logic that was previously triplicated
    inline across mart_daily_air_quality.sql and mart_health_summary.sql. The
    emitted SQL is byte-for-byte equivalent to the prior inline CASE expressions
    so mart outputs are unchanged — this is a refactor, not a behaviour change.

    Usage:
        {{ get_aqi_value('parameter', 'avg_value') }}        as aqi_value
        {{ get_aqi_category('parameter', 'avg_value') }}     as aqi_category

    Both arguments are raw SQL expressions injected into the compiled query:
      - parameter : an expression evaluating to the lower-cased pollutant code
                    (e.g. the column `parameter`, or a literal "'pm25'")
      - value     : an expression evaluating to the concentration in µg/m³
                    (e.g. `avg_value`, or an aggregate like `avg(avg_value)`)
#}

{# AQI value (0–500) via piecewise linear interpolation. NULL for non-PM/-PM10. #}
{% macro get_aqi_value(parameter, value) %}
    case
        when {{ parameter }} = 'pm25' then
            case
                when {{ value }} <=   9.0  then cast(round(( 50 -  0) / (  9.0 -  0.0) * ({{ value }} -   0.0) +   0) as int)
                when {{ value }} <=  35.4  then cast(round((100 - 51) / ( 35.4 -  9.1) * ({{ value }} -   9.1) +  51) as int)
                when {{ value }} <=  55.4  then cast(round((150 -101) / ( 55.4 - 35.5) * ({{ value }} -  35.5) + 101) as int)
                when {{ value }} <= 125.4  then cast(round((200 -151) / (125.4 - 55.5) * ({{ value }} -  55.5) + 151) as int)
                when {{ value }} <= 225.4  then cast(round((300 -201) / (225.4 -125.5) * ({{ value }} - 125.5) + 201) as int)
                when {{ value }} <= 325.4  then cast(round((500 -301) / (325.4 -225.5) * ({{ value }} - 225.5) + 301) as int)
                else 500
            end
        when {{ parameter }} = 'pm10' then
            case
                when {{ value }} <=  54.0  then cast(round(( 50 -  0) / ( 54.0 -  0.0) * ({{ value }} -   0.0) +   0) as int)
                when {{ value }} <= 154.0  then cast(round((100 - 51) / (154.0 - 55.0) * ({{ value }} -  55.0) +  51) as int)
                when {{ value }} <= 254.0  then cast(round((150 -101) / (254.0 -155.0) * ({{ value }} - 155.0) + 101) as int)
                when {{ value }} <= 354.0  then cast(round((200 -151) / (354.0 -255.0) * ({{ value }} - 255.0) + 151) as int)
                when {{ value }} <= 424.0  then cast(round((300 -201) / (424.0 -355.0) * ({{ value }} - 355.0) + 201) as int)
                when {{ value }} <= 604.0  then cast(round((500 -301) / (604.0 -425.0) * ({{ value }} - 425.0) + 301) as int)
                else 500
            end
        else null
    end
{% endmacro %}

{# AQI health category label. NULL for non-PM/-PM10 parameters or NULL value. #}
{% macro get_aqi_category(parameter, value) %}
    case
        when {{ parameter }} not in ('pm25', 'pm10') then null
        when {{ value }} is null                     then null
        when {{ parameter }} = 'pm25' then
            case
                when {{ value }} <=   9.0  then 'Good'
                when {{ value }} <=  35.4  then 'Moderate'
                when {{ value }} <=  55.4  then 'Unhealthy for Sensitive Groups'
                when {{ value }} <= 125.4  then 'Unhealthy'
                when {{ value }} <= 225.4  then 'Very Unhealthy'
                else                            'Hazardous'
            end
        when {{ parameter }} = 'pm10' then
            case
                when {{ value }} <=  54.0  then 'Good'
                when {{ value }} <= 154.0  then 'Moderate'
                when {{ value }} <= 254.0  then 'Unhealthy for Sensitive Groups'
                when {{ value }} <= 354.0  then 'Unhealthy'
                when {{ value }} <= 424.0  then 'Very Unhealthy'
                else                            'Hazardous'
            end
    end
{% endmacro %}

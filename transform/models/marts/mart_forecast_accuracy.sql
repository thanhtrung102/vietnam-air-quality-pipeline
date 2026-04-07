/*
mart_forecast_accuracy — rolling forecast error metrics per station × model.

Purpose: tracks SARIMA and Prophet forecast quality over time, enabling:
  - A/B comparison between models (which city / season is Prophet better?)
  - Early detection of model drift (rolling RMSE > 25 µg/m³ triggers SNS alarm)
  - Manual review before Phase 6 case study documentation

Sources:
  - openaq_mart.mart_daily_forecast  (Lambda-written external Parquet table)
  - mart_daily_air_quality           (dbt-managed, actuals for pm25)

Join logic:
  - For each location_id × model × forecast_date, take the MOST RECENT
    generated_at (most recent Lambda run wins when multiple forecasts exist
    for the same date — reforecasting after a data gap).
  - Left join to mart_daily_air_quality to get actual PM2.5.
    Rows with NULL actual_pm25 are days not yet observed (future forecasts)
    — these are retained in the mart but excluded from error metrics.

Error metrics (NULL when actual not yet observed):
  - error              = forecast_pm25 − actual_pm25   (positive = over-forecast)
  - abs_error          = |error|
  - squared_error      = error²

Rolling metrics (window: all rows with actual observed, ordered by forecast_date):
  - rolling_rmse_7d    = sqrt(avg(squared_error) over last 7 forecast dates)
  - rolling_rmse_30d   = sqrt(avg(squared_error) over last 30 forecast dates)
  - rolling_mae_30d    = avg(abs_error) over last 30 forecast dates
  - rolling_bias_30d   = avg(error) over last 30 forecast dates (+ = systematic over-forecast)

Grain: one row per location_id × model × forecast_date.
Partition: forecast_date (aligns with mart_daily_air_quality).

Note: mart_daily_forecast is an external table managed by the forecast_generate Lambda,
      not by dbt. It is referenced via raw Athena table path.
*/

{{ config(
    materialized      = 'table',
    partitioned_by    = ['forecast_date'],
    format            = 'parquet',
    write_compression = 'snappy'
) }}

with latest_forecasts as (

    -- Most recent forecast per station × model × forecast_date
    select
        location_id,
        location_name,
        city,
        forecast_date,
        model,
        generated_at,
        forecast_pm25,
        forecast_aqi,
        forecast_aqi_category,
        ci_lower_95,
        ci_upper_95,
        holdout_rmse,
        row_number() over (
            partition by location_id, model, forecast_date
            order by generated_at desc
        ) as rn

    from openaq_mart.mart_daily_forecast

),

actuals as (

    select
        location_id,
        avg_value   as actual_pm25,
        measurement_date

    from {{ ref('mart_daily_air_quality') }}

    where parameter          = 'pm25'
      and is_outlier_station = 0

),

matched as (

    select
        f.location_id,
        f.location_name,
        f.city,
        f.model,
        f.generated_at,
        f.forecast_pm25,
        f.forecast_aqi,
        f.forecast_aqi_category,
        f.ci_lower_95,
        f.ci_upper_95,
        f.holdout_rmse,
        a.actual_pm25,

        -- Error metrics (NULL until the forecast_date is observed in actuals)
        case
            when a.actual_pm25 is not null
            then round(f.forecast_pm25 - a.actual_pm25, 4)
        end as error,

        case
            when a.actual_pm25 is not null
            then round(abs(f.forecast_pm25 - a.actual_pm25), 4)
        end as abs_error,

        case
            when a.actual_pm25 is not null
            then round(power(f.forecast_pm25 - a.actual_pm25, 2), 4)
        end as squared_error,

        f.forecast_date

    from latest_forecasts f
    left join actuals a
           on f.location_id  = a.location_id
          and f.forecast_date = a.measurement_date

    where f.rn = 1

),

with_rolling as (

    select
        location_id,
        location_name,
        city,
        model,
        generated_at,
        forecast_pm25,
        forecast_aqi,
        forecast_aqi_category,
        ci_lower_95,
        ci_upper_95,
        holdout_rmse,
        actual_pm25,
        error,
        abs_error,
        squared_error,

        -- Rolling RMSE 7-day (only over rows that have actuals)
        round(
            sqrt(avg(squared_error) over (
                partition by location_id, model
                order by forecast_date
                rows between 6 preceding and current row
            )),
            2
        ) as rolling_rmse_7d,

        -- Rolling RMSE 30-day
        round(
            sqrt(avg(squared_error) over (
                partition by location_id, model
                order by forecast_date
                rows between 29 preceding and current row
            )),
            2
        ) as rolling_rmse_30d,

        -- Rolling MAE 30-day
        round(
            avg(abs_error) over (
                partition by location_id, model
                order by forecast_date
                rows between 29 preceding and current row
            ),
            2
        ) as rolling_mae_30d,

        -- Rolling bias 30-day (positive = systematic over-forecast)
        round(
            avg(error) over (
                partition by location_id, model
                order by forecast_date
                rows between 29 preceding and current row
            ),
            2
        ) as rolling_bias_30d,

        -- partition key last
        forecast_date

    from matched

)

select * from with_rolling

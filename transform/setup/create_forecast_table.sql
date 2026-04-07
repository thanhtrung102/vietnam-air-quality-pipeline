-- create_forecast_table.sql
-- Athena DDL for the mart_daily_forecast external table.
--
-- Written by the forecast_generate Lambda to:
--   processed/openaq_mart/mart_daily_forecast/generated_at={date}/model={model}/
--
-- Partition Projection on:
--   generated_at — DATE range (one partition per Lambda invocation day)
--   model        — ENUM (sarima | prophet)
--
-- Run against workgroup: openaq_workgroup (substitue {bucket} with actual bucket name)
-- Prerequisites: openaq_mart Glue database must exist (created by Terraform).
--
-- Re-run to recreate if schema drifts; the IF NOT EXISTS guard prevents accidental drops.

CREATE EXTERNAL TABLE IF NOT EXISTS openaq_mart.mart_daily_forecast (
    location_id           INT     COMMENT 'OpenAQ location identifier',
    location_name         STRING  COMMENT 'Canonical station name',
    city                  STRING  COMMENT 'Hanoi or Ho Chi Minh City',
    forecast_date         DATE    COMMENT 'Forecasted calendar date',
    forecast_pm25         DOUBLE  COMMENT 'Predicted daily mean PM2.5 (µg/m³)',
    forecast_aqi          INT     COMMENT 'Predicted AQI (US EPA 2024, PM2.5)',
    forecast_aqi_category STRING  COMMENT 'Predicted AQI health category label',
    ci_lower_95           DOUBLE  COMMENT '95% confidence interval lower bound (µg/m³)',
    ci_upper_95           DOUBLE  COMMENT '95% confidence interval upper bound (µg/m³)',
    holdout_rmse          DOUBLE  COMMENT '30-day holdout RMSE for this station × model (µg/m³)'
)
PARTITIONED BY (
    generated_at STRING  COMMENT 'Date the forecast was generated (YYYY-MM-DD)',
    model        STRING  COMMENT 'Model type: sarima | prophet'
)
STORED AS PARQUET
LOCATION 's3://{bucket}/processed/openaq_mart/mart_daily_forecast/'
TBLPROPERTIES (
    'parquet.compress'                = 'SNAPPY',

    -- Partition Projection: no MSCK REPAIR TABLE needed
    'projection.enabled'              = 'true',

    -- generated_at: date range from 2026-01-01 to now
    'projection.generated_at.type'   = 'date',
    'projection.generated_at.range'  = '2026-01-01,NOW',
    'projection.generated_at.format' = 'yyyy-MM-dd',

    -- model: enum
    'projection.model.type'          = 'enum',
    'projection.model.values'        = 'sarima,prophet',

    'storage.location.template'      = 's3://{bucket}/processed/openaq_mart/mart_daily_forecast/generated_at=${generated_at}/model=${model}/'
);

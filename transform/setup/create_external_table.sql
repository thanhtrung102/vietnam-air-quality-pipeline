-- Athena external table over the OpenAQ batch archive in S3.
--
-- OpenCSVSerde is required (not LazySimpleSerDe) because archive files from
-- 2024–2025 have quoted string columns while 2023 files are unquoted.
-- OpenCSVSerde handles both formats transparently.
--
-- Partition projection eliminates MSCK REPAIR TABLE overhead and enables
-- Athena to prune to a specific station/year/month without reading other
-- prefixes.
--
-- Run against workgroup: openaq_workgroup
-- Prerequisites: Glue database openaq_raw must exist (created by Terraform).

CREATE EXTERNAL TABLE IF NOT EXISTS openaq_raw.raw_measurements (
    location_id  INT     COMMENT 'OpenAQ internal location identifier',
    sensors_id   INT     COMMENT 'OpenAQ sensor identifier',
    location     STRING  COMMENT 'Human-readable station name',
    datetime     STRING  COMMENT 'ISO-8601 measurement timestamp (cast with from_iso8601_timestamp() at query time)',
    lat          FLOAT   COMMENT 'Station latitude (WGS84)',
    lon          FLOAT   COMMENT 'Station longitude (WGS84)',
    parameter    STRING  COMMENT 'Pollutant code: pm25, pm10, no2, o3, co, so2',
    units        STRING  COMMENT 'Measurement unit (µg/m³ or ppm)',
    value        FLOAT   COMMENT 'Measured concentration; sentinel -999.0 means missing'
)
PARTITIONED BY (
    locationid   STRING  COMMENT 'OpenAQ location ID — matches S3 prefix key',
    year         STRING  COMMENT 'Measurement year (YYYY)',
    month        STRING  COMMENT 'Measurement month (MM, zero-padded)'
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES (
    "separatorChar" = ",",
    "quoteChar"     = "\""
)
STORED AS TEXTFILE
LOCATION 's3://openaq-pipeline-thanhtrung102/raw/batch/'
TBLPROPERTIES (
    'skip.header.line.count' = '1',

    -- Partition projection ------------------------------------------------
    'projection.enabled'     = 'true',

    -- locationid: enum of all 21 Vietnamese station IDs
    'projection.locationid.type'   = 'enum',
    'projection.locationid.values' = '7441,2539,1285357,2161290,2161291,2161292,2161316,2161317,2161318,2161319,2161320,2161321,2161323,4946811,4946812,4946813,6123215,7440,2446,6068138,6273386',

    -- year: integer range 2023–2026
    'projection.year.type'         = 'integer',
    'projection.year.range'        = '2023,2026',

    -- month: zero-padded integer range 01–12
    'projection.month.type'        = 'integer',
    'projection.month.range'       = '1,12',
    'projection.month.digits'      = '2',

    -- S3 path template
    'storage.location.template'    = 's3://openaq-pipeline-thanhtrung102/raw/batch/locationid=${locationid}/year=${year}/month=${month}/'
);

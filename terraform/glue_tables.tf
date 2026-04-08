# ── Glue External Tables ──────────────────────────────────────────────────────
# Both tables sit in the openaq_raw Glue database and point to S3 prefixes
# already populated by the historical sync and Kinesis Firehose respectively.
#
# Batch table  : Hive-partitioned CSV.GZ  (locationid / year / month)
# Stream table : date-partitioned NDJSON  (year / month / day / hour)
#                Uses Partition Projection so no MSCK REPAIR TABLE is needed.

# ── openaq_mart database (dbt output schema) ──────────────────────────────────
# dbt writes staging views and mart tables here (schema: openaq_mart in profiles.yml).
# Previously declared as openaq_processed — renamed to match actual usage.

resource "aws_glue_catalog_database" "openaq_mart" {
  name        = "openaq_mart"
  description = "dbt staging views and mart tables produced by the transform layer"

  tags = local.common_tags
}

# ── Batch table ───────────────────────────────────────────────────────────────

resource "aws_glue_catalog_table" "openaq_batch" {
  name          = "batch"
  database_name = aws_glue_catalog_database.openaq_raw.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL                       = "TRUE"
    "skip.header.line.count"       = "1"
    "projection.enabled"           = "true"
    "projection.locationid.type"   = "enum"
    "projection.locationid.values" = local.station_ids_csv
    "projection.year.type"         = "integer"
    "projection.year.range"        = "2016,2030"
    "projection.month.type"        = "integer"
    "projection.month.range"       = "1,12"
    "projection.month.digits"      = "2"
    "storage.location.template"    = "s3://${aws_s3_bucket.main.bucket}/raw/batch/locationid=$${locationid}/year=$${year}/month=$${month}/"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.main.bucket}/raw/batch/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.serde2.OpenCSVSerde"
      parameters = {
        separatorChar = ","
        quoteChar     = "\""
      }
    }

    columns {
      name = "location_id"
      type = "int"
    }
    columns {
      name = "sensors_id"
      type = "int"
    }
    columns {
      name = "location"
      type = "string"
    }
    columns {
      name = "datetime"
      type = "string"
    }
    columns {
      name = "lat"
      type = "double"
    }
    columns {
      name = "lon"
      type = "double"
    }
    columns {
      name = "parameter"
      type = "string"
    }
    columns {
      name = "units"
      type = "string"
    }
    columns {
      name = "value"
      type = "double"
    }
  }

  # Hive-style partition keys matching the S3 prefix structure
  partition_keys {
    name = "locationid"
    type = "int"
  }
  partition_keys {
    name = "year"
    type = "int"
  }
  partition_keys {
    name = "month"
    type = "int"
  }
}

# ── Stream table ──────────────────────────────────────────────────────────────
# Kinesis Firehose writes NDJSON to raw/stream/{yyyy}/{MM}/{dd}/{HH}/.
# Partition Projection avoids MSCK REPAIR TABLE for continuously-written data.

resource "aws_glue_catalog_table" "openaq_stream" {
  name          = "stream"
  database_name = aws_glue_catalog_database.openaq_raw.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL                     = "TRUE"
    "classification"             = "json"
    "projection.enabled"         = "true"
    "projection.year.type"       = "integer"
    "projection.year.range"      = "2024,2030"
    "projection.month.type"      = "integer"
    "projection.month.range"     = "1,12"
    "projection.month.digits"    = "2"
    "projection.day.type"        = "integer"
    "projection.day.range"       = "1,31"
    "projection.day.digits"      = "2"
    "projection.hour.type"       = "integer"
    "projection.hour.range"      = "0,23"
    "projection.hour.digits"     = "2"
    "storage.location.template"  = "s3://${aws_s3_bucket.main.bucket}/raw/stream/$${year}/$${month}/$${day}/$${hour}/"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.main.bucket}/raw/stream/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
    }

    columns {
      name = "location_id"
      type = "int"
    }
    columns {
      name = "sensors_id"
      type = "int"
    }
    columns {
      name = "location"
      type = "string"
    }
    columns {
      name = "datetime"
      type = "string"
    }
    columns {
      name = "lat"
      type = "double"
    }
    columns {
      name = "lon"
      type = "double"
    }
    columns {
      name = "parameter"
      type = "string"
    }
    columns {
      name = "units"
      type = "string"
    }
    columns {
      name = "value"
      type = "double"
    }
    columns {
      name = "ingested_at"
      type = "string"
    }
  }

  partition_keys {
    name = "year"
    type = "string"
  }
  partition_keys {
    name = "month"
    type = "string"
  }
  partition_keys {
    name = "day"
    type = "string"
  }
  partition_keys {
    name = "hour"
    type = "string"
  }
}

# ── Weather table ─────────────────────────────────────────────────────────────
# Open-Meteo ERA5 hourly weather written by weather_ingest Lambda.
# Path: raw/weather/{location_id}/{yyyy}/{MM}/{dd}/weather.ndjson
# Grain: one row per location_id × date × hour_utc (24 rows/station/day).
# Partition Projection on location_id (enum) + year/month/day (integer).
# Archive tier excluded from S3 IT lifecycle — Athena requires synchronous access.

resource "aws_glue_catalog_table" "weather" {
  name          = "weather"
  database_name = aws_glue_catalog_database.openaq_raw.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL                          = "TRUE"
    "classification"                  = "json"
    "projection.enabled"              = "true"
    "projection.location_id.type"     = "enum"
    "projection.location_id.values"   = local.station_ids_csv
    "projection.year.type"            = "integer"
    "projection.year.range"           = "2016,2030"
    "projection.month.type"           = "integer"
    "projection.month.range"          = "1,12"
    "projection.month.digits"         = "2"
    "projection.day.type"             = "integer"
    "projection.day.range"            = "1,31"
    "projection.day.digits"           = "2"
    "storage.location.template"       = "s3://${aws_s3_bucket.main.bucket}/raw/weather/$${location_id}/$${year}/$${month}/$${day}/"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.main.bucket}/raw/weather/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
    }

    columns {
      name = "date"
      type = "string"
    }
    columns {
      name = "hour_utc"
      type = "int"
    }
    columns {
      name = "temperature_2m"
      type = "double"
    }
    columns {
      name = "rh_2m"
      type = "double"
    }
    columns {
      name = "wind_speed"
      type = "double"
    }
    columns {
      name = "wind_dir"
      type = "double"
    }
    columns {
      name = "precipitation_mm"
      type = "double"
    }
    columns {
      name = "surface_pressure_hpa"
      type = "double"
    }
    columns {
      name = "boundary_layer_height_m"
      type = "double"
    }
  }

  # Partition keys: location_id (enum string) + year/month/day (integer strings)
  partition_keys {
    name = "location_id"
    type = "int"
  }
  partition_keys {
    name = "year"
    type = "string"
  }
  partition_keys {
    name = "month"
    type = "string"
  }
  partition_keys {
    name = "day"
    type = "string"
  }
}

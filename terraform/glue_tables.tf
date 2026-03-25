# ── Glue External Tables ──────────────────────────────────────────────────────
# Both tables sit in the openaq_raw Glue database and point to S3 prefixes
# already populated by the historical sync and Kinesis Firehose respectively.
#
# Batch table  : Hive-partitioned CSV.GZ  (locationid / year / month)
# Stream table : date-partitioned NDJSON  (year / month / day / hour)
#                Uses Partition Projection so no MSCK REPAIR TABLE is needed.

# ── openaq_processed database (dbt output schema) ─────────────────────────────

resource "aws_glue_catalog_database" "openaq_processed" {
  name        = "openaq_processed"
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
    "projection.locationid.values" = "7441,2539,1285357,2161290,2161291,2161292,2161316,2161317,2161318,2161319,2161320,2161321,2161323,4946811,4946812,4946813,6123215,7440,2446,6068138,6273386"
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

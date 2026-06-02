+++
title = "Blog 1"
weight = 1
chapter = false
pre = " <b> 3.1. </b> "
+++

# Speed up your Amazon Athena queries using partition projection

_By Steven Wasserman, Janak Agarwal, Juan Lamadrid, and Pathik Shah — 19 May 2021, AWS Big Data Blog
([Amazon Athena](https://aws.amazon.com/blogs/big-data/category/analytics/amazon-athena/), Analytics)._

## Summary

When a table in Amazon Athena has many partitions, every query normally pays a hidden tax: Athena must
fetch the matching partitions' metadata from the AWS Glue Data Catalog (or a Hive metastore) before it
can read any data. On highly partitioned tables that metadata round-trip dominates the runtime.

**Partition projection** removes that round-trip. Instead of *looking up* partitions, you describe them
once in the table properties and Athena *computes* the partition values and their S3 locations in
memory at query time. Because in-memory generation is far cheaper than a remote metadata call, queries
against heavily partitioned tables get noticeably faster, and you no longer need a crawler or repeated
`ALTER TABLE … ADD PARTITION` calls to register new partitions.

Key points from the post:

- **How it works:** partition values and locations come from the table's `projection.*` properties, not
  from the catalog. Athena builds only the partitions the query's `WHERE` clause actually needs.
- **Projection types:** `date` (e.g. a range like `2013-10-01,NOW+12YEARS`), `integer`, `enum`, and
  `injected` (for values supplied directly in the query when they can't be generated procedurally).
- **When to use it:** highly partitioned tables, tables where you add new date/time partitions on a
  schedule, or datasets where keeping the catalog in sync is impractical.
- **Performance & cost:** customers saw large wins — Vertex cut a production query from 137 s to 10 s
  (≈92%) and month-end batch reporting from 4.5 hours to 40 minutes (≈85%); combined with compression,
  the volume of data scanned (and therefore Athena cost) drops too.
- **Limitation:** the projected partitions are understood only by Athena. Other engines (Redshift
  Spectrum, EMR) still need conventional partition metadata in the catalog.

## Applied in this project

The Vietnam Air Quality pipeline catalogs **three raw external tables** — `batch`, `stream`, and
`weather` — and every one of them uses **partition projection over date/time keys**, so **no Glue
crawler ever runs** and there is no per-scan crawl cost. New daily and hourly objects land in S3 under
Hive-style prefixes and become queryable immediately, with nothing to register. Paired with the
`openaq_workgroup` **10 GB per-query scan cap**, projection is one of the main reasons the whole
pipeline stays inside its ~$3–8/month envelope. (The streaming objects that projection reads are
produced by the Firehose path described in [Blog 2](../3.2-firehose-dynamic-partitioning/).)

**Source:** [Speed up your Amazon Athena queries using partition projection](https://aws.amazon.com/blogs/big-data/speed-up-your-amazon-athena-queries-using-partition-projection/) ·
see also the Athena docs: [Use partition projection with Amazon Athena](https://docs.aws.amazon.com/athena/latest/ug/partition-projection.html).

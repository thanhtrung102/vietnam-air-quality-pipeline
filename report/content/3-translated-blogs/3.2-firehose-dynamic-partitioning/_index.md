+++
title = "Blog 2"
weight = 2
chapter = false
pre = " <b> 3.2. </b> "
+++

# Amazon Data Firehose now supports dynamic partitioning to Amazon S3

_By Jeremy Ber and Michael Greenshtein — 2 September 2021, AWS Big Data Blog
(Analytics, Kinesis Data Firehose)._

## Summary

Amazon Data Firehose (formerly Kinesis Data Firehose) is the managed way to reliably load streaming
data into a data lake: it buffers incoming records and delivers them to Amazon S3 (and other sinks)
without any servers to run. Historically Firehose wrote objects under a default time prefix, so teams
often ran a *second* job to repartition the data into a query-friendly layout after it landed.

**Dynamic partitioning** lets Firehose do that partitioning *on the way in*. You tell Firehose how to
derive partition keys from each record, and it routes records into the right S3 prefixes before
delivery — no post-processing step.

Key points from the post:

- **Key extraction:** for JSON records you select partition keys with **jq** expressions (including
  nested fields); for non-JSON or compressed/encrypted payloads, a **Lambda** transform can decode the
  record and return the partition metadata.
- **Multi-level layouts:** keys can be combined hierarchically — e.g. `customer_id/` then device type
  then a timestamp-derived `year/month/day/` path.
- **Per-partition buffering:** Firehose maintains a separate buffer per active partition, with buffer
  sizes of **64–128 MiB** and time windows of **1–15 minutes** before it flushes to S3.
- **Limits to design for:** up to **500 active partitions** per delivery stream (soft limit) and a
  throughput ceiling per partition; records whose partition key can't be evaluated are routed to a
  dedicated **error prefix** rather than dropped.
- **Why it matters:** landing data already partitioned means analytics engines such as Athena scan only
  the relevant prefixes (partition pruning), improving performance and lowering cost downstream.

## Applied in this project

The near-real-time path of the pipeline is `streaming_producer` (Lambda, every 30 min) →
**Kinesis Data Streams** (ON_DEMAND, KMS) → **Amazon Data Firehose** → `raw/stream/`. Firehose buffers
with **GZIP compression, a 128 MB / 300 s buffer**, and writes objects under a time-based
`raw/stream/yyyy/MM/dd/HH/` layout — the same "partition on the way in" idea this post introduces. The
project deliberately uses Firehose's **timestamp namespace** partitioning rather than jq dynamic keys,
because the downstream Glue table reads those prefixes through **partition projection**
([Blog 1](../3.1-athena-partition-projection/)) — so the streaming data is queryable in Athena the
moment it lands, with no crawler and no repartitioning job. Async failures are captured by the
`openaq_streaming_dlq` SQS queue, mirroring the post's error-prefix safety net.

**Source:** [Amazon Data Firehose now supports dynamic partitioning to Amazon S3](https://aws.amazon.com/blogs/big-data/kinesis-data-firehose-now-supports-dynamic-partitioning-to-amazon-s3/).

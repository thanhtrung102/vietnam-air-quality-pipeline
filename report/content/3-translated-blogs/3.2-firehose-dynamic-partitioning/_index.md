+++
title = "Blog 2"
weight = 2
chapter = false
pre = " <b> 3.2. </b> "
+++

# Amazon Data Firehose now supports dynamic partitioning to Amazon S3

_Summarised in English from the AWS Big Data Blog post by Jeremy Ber and Michael Greenshtein —
2 September 2021 (Analytics, Kinesis Data Firehose). Original article linked at the bottom; the write-up
below is in my own words._

## Background: streaming into a query-friendly layout

Amazon Data Firehose (formerly Kinesis Data Firehose) is the managed way to load streaming data into a
data lake — it buffers incoming records and delivers them to Amazon S3 (and other destinations) with no
servers to operate. Historically Firehose wrote objects under a default time-based prefix derived from
delivery time. That works, but teams who wanted data laid out by an attribute *inside* the records
(customer, device, event date) usually ran a second job to repartition the data after it landed, adding
latency and cost.

## What dynamic partitioning adds

Dynamic partitioning lets Firehose group records into partitioned S3 prefixes **as it delivers them**,
based on values it extracts from each record. You define how the partition keys are derived and a prefix
template that places each record in the right S3 path — so the data is already query-ready when it
arrives, with no post-processing step.

## Deriving partition keys

The post describes two ways to obtain partition keys:

- **Inline parsing with jq** — for JSON records, you select fields (including nested ones) using jq
  expressions, and Firehose uses those values as partition keys.
- **A Lambda transform** — for non-JSON, compressed, or encrypted payloads, an AWS Lambda function can
  decode the record and return the partition metadata Firehose should use.

Keys can be combined into multi-level layouts — for example partition by an identifier, then a device
type, then a timestamp-derived `year/month/day/` path — to match how analysts will filter the data.

## Buffering and delivery

Firehose keeps a **separate buffer per active partition**. Buffer thresholds for dynamic partitioning
range from about **64–128 MiB** of size and **1–15 minutes** of time; whichever is reached first
triggers delivery of that partition's buffer to S3.

## Limits and error handling

There is a soft limit of roughly **500 active partitions** per delivery stream (raisable via Support)
and a per-partition throughput ceiling. Records whose partition key cannot be evaluated — for instance,
a missing field — are routed to a dedicated **error prefix** in S3 rather than dropped, so nothing is
lost silently.

## Why it matters downstream

Because the data lands already partitioned, query engines such as Athena and Redshift Spectrum can prune
to only the relevant prefixes (partition pruning), which improves query performance and lowers cost — the
same benefit covered in [Blog 1](../3.1-athena-partition-projection/).

## Applied in this project

The near-real-time path of the pipeline is `streaming_producer` (Lambda, every 30 min) →
**Kinesis Data Streams** (ON_DEMAND, KMS) → **Amazon Data Firehose** → `raw/stream/`. Firehose buffers
with **GZIP compression and a 128 MB / 300 s buffer**, writing objects under a time-based
`raw/stream/yyyy/MM/dd/HH/` layout — the same "partition on the way in" idea this post introduces. The
project deliberately uses Firehose's **timestamp-namespace** partitioning rather than jq dynamic keys,
because the downstream Glue table reads those prefixes through **partition projection** (Blog 1), so the
streaming data is queryable in Athena the moment it lands — no crawler, no repartitioning job. Async
failures are captured by the `openaq_streaming_dlq` SQS queue, mirroring the post's error-prefix safety
net.

**Source:** [Amazon Data Firehose now supports dynamic partitioning to Amazon S3](https://aws.amazon.com/blogs/big-data/kinesis-data-firehose-now-supports-dynamic-partitioning-to-amazon-s3/).

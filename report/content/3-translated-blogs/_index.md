+++
title = "Translated Blogs"
weight = 3
chapter = false
pre = " <b> 3. </b> "
+++


English write-ups of three AWS Big Data Blog articles, each chosen because it underpins a layer of
the **Vietnam Air Quality pipeline** built for this internship. Every post is summarised in English and
linked back to how the same pattern is used in this project.

## Contents

1. [Speed up your Amazon Athena queries using partition projection](3.1-athena-partition-projection/) — how partition projection computes partition locations from table config (no crawler); used on all three raw tables (`batch`, `stream`, `weather`).
2. [Amazon Data Firehose now supports dynamic partitioning to Amazon S3](3.2-firehose-dynamic-partitioning/) — how Firehose partitions streaming records on the way in; the `streaming_producer` → Kinesis → Firehose → `raw/stream/` path.
3. [How BMW Group built a serverless terabyte-scale data transformation architecture with dbt and Amazon Athena](3.3-dbt-athena-transformation/) — serverless dbt-on-Athena at scale; the 17-model staging → intermediate → marts build with 84 tests, run by CodeBuild.

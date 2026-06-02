+++
title = "Translated Blogs"
weight = 3
chapter = false
pre = " <b> 3. </b> "
+++


English write-ups of three AWS Big Data Blog articles, each chosen because it underpins a layer of
the **Vietnam Air Quality pipeline** built for this internship. Every post is summarised in English and
linked back to how the same pattern is used in this project.

### [Blog 1 - Speed up your Amazon Athena queries using partition projection](3.1-athena-partition-projection/)

How **partition projection** lets Amazon Athena compute partition locations from table configuration
instead of looking them up in the Glue Data Catalog — removing crawlers, cutting metadata round-trips,
and reducing both query latency and cost on highly partitioned tables. This is exactly the technique
the pipeline uses on all three raw tables (`batch`, `stream`, `weather`), so no crawler ever runs.

### [Blog 2 - Amazon Data Firehose now supports dynamic partitioning to Amazon S3](3.2-firehose-dynamic-partitioning/)

How **Amazon Data Firehose** organises streaming records into partitioned S3 prefixes on the way in —
per-partition buffering, key extraction, and the active-partition limits to watch. The pipeline's
near-real-time path (`streaming_producer` → Kinesis Data Streams → Firehose → `raw/stream/`) relies on
this to land time-partitioned objects that Athena then reads via partition projection (Blog 1).

### [Blog 3 - How BMW Group built a serverless terabyte-scale data transformation architecture with dbt and Amazon Athena](3.3-dbt-athena-transformation/)

How BMW Group runs ~400 **dbt** models on **Amazon Athena** in a fully serverless, layered, tested
architecture. The pipeline applies the same pattern at internship scale: 17 dbt-on-Athena models in
staging → intermediate → marts, 84 tests, a dedicated workgroup with a scan cap, run by CodeBuild.

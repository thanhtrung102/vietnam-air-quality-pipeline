+++
title = "Bài viết dịch"
weight = 3
chapter = false
pre = " <b> 3. </b> "
+++


Bản tóm lược tiếng Anh của ba bài viết trên AWS Big Data Blog, mỗi bài được chọn vì nó là nền tảng cho một tầng
của **pipeline Vietnam Air Quality** được xây dựng trong kỳ thực tập này. Mỗi bài đều được tóm tắt bằng tiếng Anh và
liên hệ trở lại cách thức cùng một mẫu thiết kế (pattern) được áp dụng trong dự án này.

## Mục lục

1. [Speed up your Amazon Athena queries using partition projection](3.1-athena-partition-projection/) — cách partition projection tính toán vị trí các partition từ cấu hình bảng (không cần crawler); được dùng trên cả ba bảng raw (`batch`, `stream`, `weather`).
2. [Amazon Data Firehose now supports dynamic partitioning to Amazon S3](3.2-firehose-dynamic-partitioning/) — cách Firehose phân vùng các bản ghi streaming ngay khi nạp vào; đường dẫn `streaming_producer` → Kinesis → Firehose → `raw/stream/`.
3. [How BMW Group built a serverless terabyte-scale data transformation architecture with dbt and Amazon Athena](3.3-dbt-athena-transformation/) — dbt-on-Athena serverless ở quy mô lớn; quá trình build 17 model staging → intermediate → marts với 84 test, chạy bởi CodeBuild.

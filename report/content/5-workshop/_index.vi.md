+++
title = "Workshop"
weight = 5
chapter = false
pre = " <b> 5. </b> "
+++


Workshop này xây dựng toàn bộ pipeline Vietnam Air Quality trên AWS từ một bản clone sạch, sử dụng
**Terraform** cho mọi tài nguyên. Quy trình có thể tái lập end-to-end và đã được kiểm chứng trực tiếp vào ngày 2026-06-01.

## Những gì bạn sẽ xây dựng

- Một **bản đồ trạm Leaflet trực tiếp** (US EPA AQI theo từng trạm) + một **dashboard phân tích 4 trang**
  (Health Scorecard, Seasonal & Weather Drivers, Compliance & Trajectory, Forecast Monitor).
- Một **dự báo PM2.5 7 ngày bằng SARIMA** (container Lambda) với giám sát RMSE qua CloudWatch.
- **Hạ tầng tái lập hoàn toàn** — một lệnh `terraform apply` cung cấp ~82 tài nguyên.

> QuickSight là **tùy chọn** (nó yêu cầu Enterprise edition). Bản triển khai này chạy trên QuickSight
> Standard, nên tầng BI được cung cấp bằng một **dashboard tĩnh nằm trong giới hạn chi phí** (Leaflet + Chart.js)
> đọc cùng các mart dbt thông qua Lambda `aqi_api`. Các file `quicksight_*.tf` được để riêng trong
> `terraform/_qs_disabled/`.

## Tổng quan các điều kiện tiên quyết

- Tài khoản AWS + IAM user kiểu `terraform-admin` (region `ap-southeast-1`).
- Terraform ≥ 1.10, AWS CLI, Python 3.12, một OpenAQ API key.
- Xem **5.2 Điều kiện tiên quyết**.

## Thứ tự build có thể tái lập

| Bước | Phần | Kết quả |
|---|---|---|
| 1 | 5.2 Điều kiện tiên quyết | công cụ, thông tin xác thực, `terraform.tfvars` |
| 2 | 5.3 Storage & Catalog | S3, Glue (partition projection), Athena |
| 3 | 5.4 Ingestion | 3 Lambda, Kinesis/Firehose, lịch EventBridge |
| 4 | 5.5 Transform & Serving | dbt-on-Athena, API + dashboard, dự báo SARIMA, bảo mật |
| 5 | 5.6 Cleanup | dọn dẹp toàn bộ |

Runbook song ngữ đầy đủ nằm trong repo dưới `docs/workshop/5.1`–`5.6`.

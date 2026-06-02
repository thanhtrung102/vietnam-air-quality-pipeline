+++
title = "Báo cáo Thực tập AWS FCJ"
description = "AWS First Cloud Journey internship report — a fully serverless Vietnamese air-quality data pipeline (OpenAQ + ERA5 → S3 → Glue → Athena/dbt → API + ML forecast)."
+++

# Vietnam Air Quality Pipeline — Báo cáo Thực tập AWS First Cloud Journey

Một **pipeline kỹ thuật dữ liệu hoàn toàn serverless** trên AWS, thực hiện thu thập, biến đổi, phục vụ và dự báo
dữ liệu chất lượng không khí cho **21 trạm quan trắc tại Việt Nam** (Hà Nội + Thành phố Hồ Chí Minh), được xây dựng và vận hành
trong giới hạn chi phí nghiêm ngặt **~$3–8/tháng** cho một người vận hành duy nhất.

> **Sản phẩm trực tiếp (live)**
> - Bản đồ trạm + dashboard phân tích (trang tĩnh S3): `http://openaq-pipeline-thanhtrung102.s3-website-ap-southeast-1.amazonaws.com/dashboard/index.html`
> - Kho mã nguồn: `https://github.com/thanhtrung102/vietnam-air-quality-pipeline`

## Nội dung báo cáo

Báo cáo này tuân theo cấu trúc báo cáo thực tập AWS FCJ. Tất cả các phần đều đã được viết, ngoại trừ **Phần 4
(Sự kiện tham gia)** vẫn đang ở trạng thái đang cập nhật; Đề xuất dự án và Workshop đã được kiểm chứng end-to-end.

| # | Phần | Trạng thái |
|---|---|---|
| 1 | **Nhật ký công việc** | ✅ 8 tuần |
| 2 | **Đề xuất dự án** | ✅ hoàn thành |
| 3 | **Bài viết dịch** | ✅ 3 bài |
| 4 | Sự kiện tham gia | _đang cập nhật_ |
| 5 | **Workshop** | ✅ hoàn thành + tái lập được |
| 6 | **Tự đánh giá** | ✅ hoàn thành |
| 7 | **Chia sẻ và Phản hồi** | ✅ hoàn thành |

## Tổng quan nhanh (đã kiểm chứng trực tiếp, 2026-06-01)

- **6 Lambda** (python3.12 / arm64), streaming với Kinesis + Firehose, Glue partition projection, Athena +
  **dbt** (17 model, **84 test**), dự báo 7 ngày bằng **SARIMA**, API Gateway + dashboard Leaflet/Chart.js.
- **Tái lập được**: mọi tài nguyên đều bằng Terraform; một bản clone mới triển khai ra ~82 tài nguyên.
- **Well-Architected**: đã rà soát 6 trụ cột; 14 cảnh báo CloudWatch + một AWS Budget; không còn rủi ro cao nào tồn đọng.

## Người đóng góp

{{< ghcontributors "https://api.github.com/repos/thanhtrung102/vietnam-air-quality-pipeline/contributors" >}}

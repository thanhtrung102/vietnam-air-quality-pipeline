+++
title = "Nhật ký công việc Tuần 7"
weight = 7
chapter = false
pre = " <b> 1.7. </b> "
+++

**Dự án:** OTT Data Analyst Agent
([aws-fcj-ott-data-analyst-agent](https://github.com/thanhtrung102/aws-fcj-ott-data-analyst-agent)) →
Củng cố Vietnam AQ
([vietnam-air-quality-pipeline](https://github.com/thanhtrung102/vietnam-air-quality-pipeline))

### Mục tiêu Tuần 7 (28–31 May 2026)

- Xây dựng một **OTT Data Analyst Agent** chạy trên Bedrock dưới dạng FCJ workshop (Hugo + AWS CDK).
- Quay lại pipeline chất lượng không khí để **củng cố bảo mật/khả năng quan sát**.
- Cài đặt một **governance harness** và áp dụng một backend **remote Terraform state** bền vững.

### Công việc thực hiện trong tuần

| Ngày | Công việc | Bắt đầu | Hoàn thành | Commit |
| :-- | :--- | :--- | :--- | :--- |
| 1 | **OTT Data Analyst Agent** — dựng khung FCJ workshop "OTT Data Analyst Agent" (Hugo + **AWS CDK**); xác minh end-to-end — 3 stack đã triển khai, 5 truy vấn phân tích đạt yêu cầu, và single-page app đã hoạt động; sửa script invoke để nhắm đúng stack/region. | 28/05/2026 | 28/05/2026 | [`e7d35a5`], [`d4a5992`], [`6bce4af`] |
| 2 | **Củng cố bảo mật & khả năng phục hồi AQ** — khóa OpenAQ chỉ-qua-secret, các **DLQ** SQS, SSE, danh sách trạm nguồn-duy-nhất; vô hiệu hóa QuickSight để ưu tiên dashboard tĩnh; củng cố việc phân tích dòng dữ liệu trong Lambda bằng raise-not-exit và **RMSE dự báo walk-forward**; unit test cho các Lambda ingestion; trích xuất các macro AQI của dbt và gắn tag `bi_disabled` cho các mart chẩn đoán; các chỉ số lỗi-âm-thầm + cảnh báo CloudWatch; hoàn tất image dbt CodeBuild; báo cáo đã xác minh trực tiếp + một lượt rà soát verify-as-source-of-truth. | 29/05/2026 | 30/05/2026 | [`12d3d0d`], [`9673e20`], [`5f23455`], [`2f98e25`] |
| 3 | **Governance & độ bền vững AQ** — cổng kiểm tra độ tươi nguồn dbt dựa trên truy vấn + một test khí tượng; cài đặt **RIPER-5 agent harness** với một HARD GATE trạng thái trực tiếp (bộ audit đạt yêu cầu); gỡ bỏ một trích dẫn `corrected_pm25` bịa đặt và gán nhãn lại nó như một heuristic chưa được xác thực; áp dụng backend **remote S3 Terraform state** với lockfile S3 gốc (không dùng DynamoDB). | 31/05/2026 | 31/05/2026 | [`424e33b`], [`092c037`], [`19511db`], [`d720baf`] |

### Thành quả Tuần 7

- **Một agent phân tích dữ liệu chạy Bedrock đã triển khai** (CDK, 3 stack) trả lời các câu hỏi phân tích trên
  một tập dữ liệu OTT, với một front end SPA trực tiếp.
- **Pipeline AQ đã được củng cố cho production**: thông tin xác thực chỉ-qua-secret, các DLQ, SSE, reserved concurrency, và
  các cảnh báo lỗi-âm-thầm.
- **BI tự chủ**: QuickSight (chỉ có ở bản Enterprise) được thay bằng dashboard tĩnh Leaflet + Chart.js,
  giữ trong khung chi phí.
- **State bền vững + governance**: một backend remote S3 với khóa gốc, và một RIPER-5 harness
  bắt buộc xác minh trạng thái trực tiếp trước khi các thay đổi được phát hành.

---

👉 **Kết quả:** Một sản phẩm OTT thứ ba (agent) đã được phát hành, và pipeline chất lượng không khí đã được nâng
lên chất lượng portfolio — được bảo mật, có thể quan sát, đã kiểm thử, được quản trị, và có thể tái lập từ trạng thái sạch.

[`e7d35a5`]: https://github.com/thanhtrung102/aws-fcj-ott-data-analyst-agent/commit/e7d35a5
[`d4a5992`]: https://github.com/thanhtrung102/aws-fcj-ott-data-analyst-agent/commit/d4a5992
[`6bce4af`]: https://github.com/thanhtrung102/aws-fcj-ott-data-analyst-agent/commit/6bce4af
[`12d3d0d`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/12d3d0d
[`9673e20`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/9673e20
[`5f23455`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/5f23455
[`2f98e25`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/2f98e25
[`424e33b`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/424e33b
[`092c037`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/092c037
[`19511db`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/19511db
[`d720baf`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/d720baf

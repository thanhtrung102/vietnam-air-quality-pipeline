+++
title = "Nhật ký công việc Tuần 1"
weight = 1
chapter = false
pre = " <b> 1.1. </b> "
+++

**Dự án:** Vietnam Air Quality pipeline ·
[vietnam-air-quality-pipeline](https://github.com/thanhtrung102/vietnam-air-quality-pipeline)

### Mục tiêu Tuần 1 (25–29 Mar 2026)

- Thiết lập repository, phát biểu bài toán, kiến trúc và danh sách các trạm quan trắc tại Việt Nam.
- Cấp phát hạ tầng AWS cốt lõi dưới dạng **Terraform** (S3, Glue, Athena, Kinesis, IAM, CloudWatch).
- Dựng phần **ingestion**: nạp dữ liệu lịch sử theo lô từ kho lưu trữ OpenAQ trên S3 và một producer
  streaming gần thời gian thực.
- Lập catalog cho dữ liệu thô bằng **Glue partition projection** (không dùng crawler) và xây dựng các **dbt** mart đầu tiên.
- Bàn giao **lát cắt end-to-end** đầu tiên: bản đồ trạm Leaflet trực tiếp được phục vụ bởi một API trên các mart AQI.

### Công việc thực hiện trong tuần

| Ngày | Công việc | Bắt đầu | Hoàn thành | Commit |
| :-- | :--- | :--- | :--- | :--- |
| 1 | **Nền tảng dự án & IaC** — cấu trúc repository, phát biểu bài toán, tài liệu kiến trúc + ADRs, khảo sát ID trạm/kho lưu trữ của Việt Nam; stack Terraform đầu tiên cho S3, Glue, Athena, Kinesis, IAM, CloudWatch; script đồng bộ lịch sử S3 + đồng bộ tăng dần hằng ngày; producer Kinesis cho OpenAQ API v3. | 25/03/2026 | 25/03/2026 | [`649b096`], [`4e65a5a`], [`c452e9c`] |
| 2 | **Điều phối & các mart đầu tiên** — thay thế kế hoạch Kestra/Docker bằng **EventBridge Scheduler + Lambda**; viết lại `batch_sync` để dùng **boto3**; bảng external Athena với **partition projection** + OpenCSVSerde; các mô hình dbt staging → intermediate → mart cùng seed metadata trạm; chỉ số AQI + cờ vượt ngưỡng; bản đồ Leaflet, đồng bộ theo sự kiện SNS, và endpoint `aqi_api`. | 26/03/2026 | 26/03/2026 | [`7048c9a`], [`19523f7`], [`f6069eb`] |
| 3 | **Kể chuyện trên dashboard & tối ưu hóa** — các view tương đương điếu thuốc, mức tuân thủ WHO và tóm tắt sức khỏe; một lượt tối ưu về tính đúng đắn/chi phí/độ phủ kiểm thử; tinh chỉnh warehouse và định dạng dbt. | 27/03/2026 | 27/03/2026 | [`971fae0`], [`4e4fbe5`] |
| 4 | **Dọn dẹp lỗi & tài liệu** — sửa các lỗi mã nghiêm trọng và mã chết; gỡ các điểm nghẽn build dbt; xác thực vị trí mart trên S3; hoàn thiện README; bổ sung các cải tiến dashboard QuickSight ban đầu và sơ đồ kiến trúc đầu tiên. | 28/03/2026 | 28/03/2026 | [`1e72f8d`], [`522f39c`] |
| 5 | **Củng cố độ chính xác dữ liệu** — kết xuất các giao diện dashboard thành ảnh tĩnh và sửa các lỗi độ chính xác dữ liệu phát hiện được khi đối chiếu với số liệu thống kê OpenAQ thực tế (bao gồm lọc một giá trị sentinel từ một trạm tại TP.HCM). | 29/03/2026 | 29/03/2026 | [`5cdeea5`], [`fa7415c`] |

### Thành quả Tuần 1

- **Một pipeline end-to-end hoạt động** chỉ trong một tuần: kho lưu trữ OpenAQ + API → S3 → Glue (partition projection)
  → các mart Athena/dbt → `aqi_api` → bản đồ Leaflet trực tiếp.
- **Điều phối ưu tiên serverless** dùng EventBridge Scheduler + Lambda sau khi Docker/Kestra tỏ ra
  không khả dụng — một quyết định kiến trúc sớm định hình toàn bộ dự án.
- **Logic AQI theo chuẩn US EPA** và các cờ vượt ngưỡng được tính trong dbt, kèm theo mức tuân thủ WHO và khung sức khỏe trên dashboard.
- **Nền tảng tối ưu chi phí**: partition projection (không crawler) và một workgroup Athena giới hạn dung lượng quét.

---

👉 **Kết quả:** Đến cuối Tuần 1, pipeline đã tạo ra kết quả chất lượng không khí thực tế, hướng đến sức khỏe từ
danh sách trạm quan trắc tại Việt Nam, theo dạng end-to-end, trên một stack hoàn toàn serverless.

[`649b096`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/649b096
[`4e65a5a`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/4e65a5a
[`c452e9c`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/c452e9c
[`7048c9a`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/7048c9a
[`19523f7`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/19523f7
[`f6069eb`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/f6069eb
[`971fae0`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/971fae0
[`4e4fbe5`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/4e4fbe5
[`1e72f8d`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/1e72f8d
[`522f39c`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/522f39c
[`5cdeea5`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/5cdeea5
[`fa7415c`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/fa7415c

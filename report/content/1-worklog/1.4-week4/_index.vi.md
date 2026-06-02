+++
title = "Nhật ký công việc Tuần 4"
weight = 4
chapter = false
pre = " <b> 1.4. </b> "
+++

**Dự án:** OTT Search Analytics pipeline ·
[ott-search-pipeline](https://github.com/thanhtrung102/ott-search-pipeline)

### Mục tiêu Tuần 4 (7–12 May 2026)

- Xây dựng pipeline **phân tích tìm kiếm OTT tiếng Việt** (người dùng tìm kiếm gì trên một dịch vụ streaming,
  và họ rời bỏ ở đâu).
- Phân loại các truy vấn tìm kiếm dạng văn bản tự do thành **thể loại** bằng cách tiếp cận lai rule + LLM.
- Đóng gói thành một FCJ workshop với kết quả đã được kiểm chứng và có thể tái lập.

### Công việc thực hiện trong tuần

| Ngày | Công việc | Bắt đầu | Hoàn thành | Commit |
| :-- | :--- | :--- | :--- | :--- |
| 1 | **Khung pipeline** — pipeline phân tích tìm kiếm OTT tiếng Việt ban đầu; sửa các lỗ hổng tái lập workshop nghiêm trọng phát hiện qua một lượt audit codebase. | 07/05/2026 | 07/05/2026 | [`8d789c0`], [`b85de84`] |
| 2 | **Workshop & chỉ số** — thêm một site Hugo workshop và sửa quyền IAM của stack governance; chỉnh các sai lệch tỷ lệ rời bỏ; thêm trang đề xuất FCJ; viết lại nội dung workshop với minh chứng kết quả đã kiểm chứng. | 08/05/2026 | 08/05/2026 | [`28c353b`], [`5dd9f43`], [`2554711`] |
| 3 | **Bộ phân loại thể loại** — chuẩn hóa dấu tiếng Việt, mở rộng LUT (lookup-table), và sửa regex; sửa lỗi timeout của Glue (bỏ qua giai đoạn fuzzy ở chế độ nhanh); cải thiện precision/recall; thêm **dự phòng Amazon Bedrock (Nova)** trong Lambda; xây dựng `evaluate_classifier.py` để đánh giá chất lượng trên toàn bộ tập dữ liệu; mở rộng LUT đã tuyển chọn với **409 mục đã thẩm định** cùng một tập kiểm thử ground-truth. | 11/05/2026 | 11/05/2026 | [`7a265b7`], [`9001db1`], [`7e79284`], [`78bfeb4`] |
| 4 | **Làm giàu dữ liệu end-to-end** — sửa pipeline ingestion và làm giàu tập dữ liệu production theo dạng end-to-end. | 12/05/2026 | 12/05/2026 | [`5a4d88c`] |

### Thành quả Tuần 4

- **Một pipeline phân tích tìm kiếm OTT hoạt động** biến nhật ký tìm kiếm thô thành phân tích đã phân loại
  thể loại và nhận biết hành vi rời bỏ.
- **Một bộ phân loại thể loại lai**: một bảng tra cứu được tuyển chọn nhận biết dấu tiếng Việt để đảm bảo độ chính xác,
  cùng dự phòng Amazon Bedrock (Nova) cho các truy vấn lạ — được đánh giá dựa trên một tập ground-truth thay vì
  phỏng đoán.
- **Workshop có thể tái lập**: nội dung FCJ workshop được viết lại xoay quanh các con số đã kiểm chứng, có
  minh chứng kết quả, sau một lượt audit khả năng tái lập.

---

👉 **Kết quả:** Một dự án dữ liệu AWS thứ hai đã được bàn giao — phân tích hành vi tìm kiếm với một bước phân loại
NLP có thể đo lường, đã được đánh giá, kèm theo một FCJ workshop.

[`8d789c0`]: https://github.com/thanhtrung102/ott-search-pipeline/commit/8d789c0
[`b85de84`]: https://github.com/thanhtrung102/ott-search-pipeline/commit/b85de84
[`28c353b`]: https://github.com/thanhtrung102/ott-search-pipeline/commit/28c353b
[`5dd9f43`]: https://github.com/thanhtrung102/ott-search-pipeline/commit/5dd9f43
[`2554711`]: https://github.com/thanhtrung102/ott-search-pipeline/commit/2554711
[`7a265b7`]: https://github.com/thanhtrung102/ott-search-pipeline/commit/7a265b7
[`9001db1`]: https://github.com/thanhtrung102/ott-search-pipeline/commit/9001db1
[`7e79284`]: https://github.com/thanhtrung102/ott-search-pipeline/commit/7e79284
[`78bfeb4`]: https://github.com/thanhtrung102/ott-search-pipeline/commit/78bfeb4
[`5a4d88c`]: https://github.com/thanhtrung102/ott-search-pipeline/commit/5a4d88c

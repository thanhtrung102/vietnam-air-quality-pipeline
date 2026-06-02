+++
title = "Nhật ký công việc Tuần 8"
weight = 8
chapter = false
pre = " <b> 1.8. </b> "
+++

**Dự án:** Vietnam Air Quality pipeline ·
[vietnam-air-quality-pipeline](https://github.com/thanhtrung102/vietnam-air-quality-pipeline)

### Mục tiêu Tuần 8 (1–2 Jun 2026)

- Định khung **bối cảnh kinh doanh** của dự án cho đề xuất FCJ.
- Làm cho **workshop có thể tái lập end-to-end** trên một máy mới và xác minh nó trực tiếp.
- Hoàn thiện **hệ thống con dự báo** và phần củng cố **chất lượng dữ liệu L4**.
- Xây dựng và triển khai **site báo cáo thực tập FCJ** và xác minh toàn bộ hệ thống trực tiếp.

### Công việc thực hiện trong tuần

| Ngày | Công việc | Bắt đầu | Hoàn thành | Commit |
| :-- | :--- | :--- | :--- | :--- |
| 1 | **Định khung kinh doanh & khả năng tái lập** — soạn `BUSINESS-CONTEXT.md` (định khung đề xuất/kinh doanh FCJ); làm cho workshop **5.1–5.6 có thể tái lập end-to-end** trên một máy mới; sửa **hệ thống con dự báo SARIMA**; hoàn tất củng cố **chất lượng dữ liệu L4**; bàn giao dashboard phân tích thay thế QuickSight; đối chiếu drift `bi_disabled` và ngưỡng chi phí. | 01/06/2026 | 01/06/2026 | [`2df9fc2`], [`adbbb27`], [`08f40d8`], [`192b8af`], [`9db52f2`] |
| 2 | **Site báo cáo FCJ & xác minh trực tiếp** — xây dựng **site báo cáo thực tập Hugo** (hugo-theme-learn, bảng màu AWS workshop) với phần Proposal, Workshop, Translated Blogs và Worklog này; audit sơ đồ kiến trúc; xác minh pipeline đã triển khai **trực tiếp end-to-end** — 5 trạm đang hoạt động, một bản dự báo 7 ngày 35 dòng, dbt 84/84 test, và AWS Budget $8. | 01/06/2026 | 02/06/2026 | [`d1803ee`], [`0674ab5`], [`ea527d9`], [`03f31d8`] |

### Thành quả Tuần 8

- **Đề xuất gắn với kinh doanh**: một phát biểu bài toán rõ ràng, các mục tiêu và tiêu chí thành công gắn với
  phần kỹ thuật.
- **Có thể tái lập từ đầu**: workshop triển khai toàn bộ stack bằng Terraform và đã được xác nhận
  build được từ một bản clone sạch.
- **Hoàn thiện dự báo & chất lượng dữ liệu**: một hệ thống con SARIMA đã sửa đúng và một bộ kiểm thử đã củng cố
  (84 test, tất cả đều pass).
- **Một báo cáo thực tập trực tiếp**: site này, xuất bản lên GitHub Pages, với mọi chỉ số tiêu đề đều được
  xác minh đối chiếu với tài khoản AWS đang chạy.

---

👉 **Kết quả:** Sản phẩm bàn giao chính của kỳ thực tập đã được hoàn thành, có thể tái lập, và được tài liệu hóa thành
một báo cáo FCJ trực tiếp — với tất cả tiêu chí thành công đều được đáp ứng và xác minh đối chiếu với hệ thống đã triển khai.

[`2df9fc2`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/2df9fc2
[`adbbb27`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/adbbb27
[`08f40d8`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/08f40d8
[`192b8af`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/192b8af
[`9db52f2`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/9db52f2
[`d1803ee`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/d1803ee
[`0674ab5`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/0674ab5
[`ea527d9`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/ea527d9
[`03f31d8`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/03f31d8

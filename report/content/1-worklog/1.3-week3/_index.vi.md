+++
title = "Nhật ký công việc Tuần 3"
weight = 3
chapter = false
pre = " <b> 1.3. </b> "
+++

**Dự án:** Vietnam Air Quality pipeline ·
[vietnam-air-quality-pipeline](https://github.com/thanhtrung102/vietnam-air-quality-pipeline)

### Mục tiêu Tuần 3 (9–18 Apr 2026)

- Triển khai tầng **business intelligence** (Amazon QuickSight) trên các mart.
- Kết nối để **build dbt hằng ngày** chạy tự động.
- **Xác thực workshop** (5.1–5.6) theo từng trang đối chiếu với codebase thực tế và template FCJ.
- Áp dụng các cải tiến **Well-Architected** và sửa các điểm nghẽn tái lập.

### Công việc thực hiện trong tuần

| Ngày | Công việc | Bắt đầu | Hoàn thành | Commit |
| :-- | :--- | :--- | :--- | :--- |
| 1 | **BI với QuickSight** — triển khai QuickSight Phase 1+2 (IAM, nguồn dữ liệu Athena, 9 dataset SPICE), rồi Phase 3+4 (analysis, dashboard, DIRECT_QUERY); kết nối **build dbt hằng ngày** và sửa target EventBridge → CodeBuild. | 10/04/2026 | 14/04/2026 | [`911006e`], [`a3c50a0`], [`701b3de`] |
| 2 | **Mở rộng dashboard & sức khỏe mã** — mở rộng dashboard bằng các trường thô trước đó chưa dùng; một lượt rà soát sức khỏe mã (import chết, đặt tên boolean, khử trùng lặp mart); sửa các test bị hỏng; các phần tài liệu và điều hướng FCJ. | 15/04/2026 | 15/04/2026 | [`7709676`], [`0532e99`], [`d04a071`] |
| 3 | **Kiểm chứng workshop** — kiểm chứng và xác thực **các trang workshop 5.1–5.6** đối chiếu với codebase và template mẫu FCJ (số lượng cảm biến, lịch chạy, số lượng tài nguyên, tên gọi, output, định dạng response); thêm sơ đồ `architecture.yaml` (diagram-as-code) và sửa một lỗ hổng XSS trên dashboard. | 16/04/2026 | 16/04/2026 | [`b58fbc3`], [`3c1c407`], [`e9a3323`] |
| 4 | **Well-Architected & khả năng tái lập** — áp dụng các cải tiến Well-Architected (arm64, X-Ray, right-sizing, độ tin cậy); thêm phần workshop QuickSight và hạ tầng website tĩnh S3; sửa hai điểm nghẽn tái lập phát hiện khi rà soát. | 17/04/2026 | 17/04/2026 | [`0230a1f`], [`f70888c`], [`74e919a`] |
| 5 | **Tính đúng đắn & xác minh trực tiếp** — sửa lỗi GROUP BY trong `mart_daily_air_quality` và cập nhật tài liệu workshop với các giá trị **đã được xác minh trực tiếp**. | 18/04/2026 | 18/04/2026 | [`c69c412`] |

### Thành quả Tuần 3

- **Đã bàn giao tầng BI**: analysis + dashboard QuickSight trên các mart, với build dbt hằng ngày
  được tự động hóa qua CodeBuild.
- **Một workshop đã xác thực, có thể tái lập**: mọi trang 5.x đều được kiểm chứng đối chiếu với codebase trực tiếp và template FCJ.
- **Một lượt Well-Architected**: Lambda arm64, tracing, right-sizing và các bản sửa độ tin cậy.
- **Một sơ đồ kiến trúc với icon AWS** được sinh ra từ một file định nghĩa (diagram-as-code).

---

👉 **Kết quả:** Đến cuối Tuần 3, dự án đã có một tầng BI, một build hằng ngày tự động và một
runbook workshop với mọi tuyên bố đều đã được kiểm chứng đối chiếu với hệ thống đang chạy.

[`911006e`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/911006e
[`a3c50a0`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/a3c50a0
[`701b3de`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/701b3de
[`7709676`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/7709676
[`0532e99`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/0532e99
[`d04a071`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/d04a071
[`b58fbc3`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/b58fbc3
[`3c1c407`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/3c1c407
[`e9a3323`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/e9a3323
[`0230a1f`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/0230a1f
[`f70888c`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/f70888c
[`74e919a`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/74e919a
[`c69c412`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/c69c412

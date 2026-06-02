+++
title = "Nhật ký công việc Tuần 2"
weight = 2
chapter = false
pre = " <b> 1.2. </b> "
+++

**Dự án:** Vietnam Air Quality pipeline ·
[vietnam-air-quality-pipeline](https://github.com/thanhtrung102/vietnam-air-quality-pipeline)

### Mục tiêu Tuần 2 (30 Mar–8 Apr 2026)

- Đào sâu **chất lượng dữ liệu**: các cờ điểm bất thường và sai lệch cảm biến, các lỗ hổng độ tin cậy từ
  IoT Well-Architected Lens.
- Bổ sung các mart và biểu đồ **phân tích chẩn đoán** vượt ra ngoài view AQI hằng ngày cơ bản.
- Nạp **biến khí tượng** (Open-Meteo ERA5) và xây dựng các đặc trưng dự báo.
- Xây dựng **dự báo PM2.5 7 ngày** và triển khai dưới dạng container Lambda.
- Tái cấu trúc tài liệu theo định dạng **FCJ workshop** kèm sơ đồ kiến trúc.

### Công việc thực hiện trong tuần

| Ngày | Công việc | Bắt đầu | Hoàn thành | Commit |
| :-- | :--- | :--- | :--- | :--- |
| 1 | **Chất lượng dữ liệu & Phase 0–2** — các cờ điểm bất thường/sai lệch cảm biến; hoàn tất phần việc Phase 0 còn dở (7 bổ sung mart/dashboard); Phase 1 đóng 7 lỗ hổng độ tin cậy IoT Well-Architected; Phase 2 thêm 2 mart chẩn đoán + 2 biểu đồ. | 30/03/2026 | 06/04/2026 | [`98e613b`], [`3ec39f6`], [`05aa59a`] |
| 2 | **Khí tượng, đặc trưng & dự báo (Phase 3–6)** — nạp **ERA5** từ Open-Meteo + 4 mô hình dbt khí tượng; xây dựng đặc trưng dự báo (mart lag, thống kê đặc trưng, seed ngày lễ); Lambda dự báo SARIMA + Prophet + một sheet dashboard dự báo; tài liệu case-study CRISP-DM. | 07/04/2026 | 07/04/2026 | [`a7278d0`], [`e678e83`], [`4dc9a12`] |
| 3 | **Triển khai dự báo & cơ chế bảo vệ** — triển khai một **container Lambda ECR chỉ dùng SARIMA** cho dự báo PM2.5 7 ngày; thêm cơ chế bảo vệ chống dữ liệu cũ và kiểm tra tính đầy đủ thông minh hơn; sửa năm lỗi tính đúng đắn Athena/dbt phát hiện trong một lượt tái lập. | 07/04/2026 | 07/04/2026 | [`3884ef0`], [`5b11bd5`], [`7d03256`] |
| 4 | **Cấu trúc tài liệu FCJ** — thay thế tài liệu rời rạc bằng **cấu trúc FCJ workshop**; tạo sơ đồ kiến trúc draw.io và sửa các điểm không khớp với codebase trong đó; bổ sung unit test + tự động hóa sau triển khai. | 08/04/2026 | 08/04/2026 | [`6ac7231`], [`1c38020`], [`9321978`] |

### Thành quả Tuần 2

- **Phân tích có yếu tố khí tượng**: các biến ERA5 được join vào các mart, cho phép phân tích theo mùa/yếu tố thời tiết.
- **Tầng dự báo đã hoạt động**: dự báo PM2.5 7 ngày bằng SARIMA chạy dưới dạng container Lambda, kèm cơ chế
  bảo vệ chống dữ liệu cũ và kiểm tra tính đầy đủ.
- **Chiều sâu chẩn đoán**: các mart và biểu đồ bổ sung đã đưa dashboard từ mô tả sang chẩn đoán.
- **Tài liệu theo chuẩn FCJ**: tài liệu của repository được tái cấu trúc theo định dạng workshop dùng trong báo cáo này.

---

👉 **Kết quả:** Đến cuối Tuần 2, pipeline không chỉ mang tính mô tả mà đã trở nên **có khả năng dự báo và
nhận biết yếu tố khí tượng**, đồng thời tài liệu đã được tổ chức lại theo định dạng FCJ workshop.

[`98e613b`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/98e613b
[`3ec39f6`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/3ec39f6
[`05aa59a`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/05aa59a
[`a7278d0`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/a7278d0
[`e678e83`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/e678e83
[`4dc9a12`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/4dc9a12
[`3884ef0`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/3884ef0
[`5b11bd5`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/5b11bd5
[`7d03256`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/7d03256
[`6ac7231`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/6ac7231
[`1c38020`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/1c38020
[`9321978`]: https://github.com/thanhtrung102/vietnam-air-quality-pipeline/commit/9321978

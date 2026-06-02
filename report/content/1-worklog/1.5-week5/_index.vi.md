+++
title = "Nhật ký công việc Tuần 5"
weight = 5
chapter = false
pre = " <b> 1.5. </b> "
+++

**Dự án:** OTT SDLF data-lake pipeline ·
[ott-sdlf](https://github.com/thanhtrung102/ott-sdlf)

### Mục tiêu Tuần 5 (13–19 May 2026)

- Xây dựng một data lake phân tích OTT trên AWS **Serverless Data Lake Framework (SDLF)**.
- Bàn giao các **Lambda phân tích** (khoảng trống nội dung và từ khóa thịnh hành) trên tầng curated.
- Dựng **CI/CD thuần AWS** (CodePipeline + CodeConnections) cho toàn bộ stack.
- Bổ sung **bảo mật chi tiết** (phân quyền cấp cột bằng Lake Formation) và một **API** phục vụ.

### Công việc thực hiện trong tuần

| Ngày | Công việc | Bắt đầu | Hoàn thành | Commit |
| :-- | :--- | :--- | :--- | :--- |
| 1 | **Tầng phân tích + CI/CD** — các Lambda phân tích Content Gap và Trending Keywords (heatmap theo giờ, nhu cầu khách/đã xác thực, rời bỏ theo mạng lưới); một dashboard HTML trong Lambda Content Gap; một stack CI/CD **CodePipeline** thuần AWS (qua CodeConnections); một giai đoạn gold CTAS + chất lượng dữ liệu gold; một workgroup Athena `sdlf-ott` và một Glue job bookmark. | 13/05/2026 | 13/05/2026 | [`637f64f`], [`f9e718c`], [`8443b26`], [`7dfea60`] |
| 2 | **Bảo mật chi tiết + API** — **phân quyền cấp cột bằng Lake Formation** trên `user_id_hashed`; một **HTTP API Gateway** (`GET /trending`, `GET /content-gaps`); hợp nhất các stack DQ thành một template tham số hóa duy nhất (mẫu SDLF); đăng ký toàn bộ dữ liệu chưa lập catalog vào Glue catalog. | 14/05/2026 | 14/05/2026 | [`4b3970f`], [`30ec606`], [`39a2414`], [`07faa0e`] |
| 3 | **Thiết kế cơ sở dữ liệu & tính đúng đắn** — áp dụng 9 bản sửa thiết kế cơ sở dữ liệu trên schema, catalog và API; sửa các lỗi nghiêm trọng của Glue job và thiết lập một hợp đồng schema cho curated-catalog; xử lý toàn bộ 11 phát hiện đánh giá còn lại; viết tài liệu pipeline toàn diện (10 phần). | 15/05/2026 | 15/05/2026 | [`6a7593f`], [`d95b4d4`], [`888a196`], [`cc9a33a`] |

### Thành quả Tuần 5

- **Một data lake SDLF hoàn chỉnh** cho phân tích OTT: raw → curated → gold, vận hành theo mẫu giai đoạn
  của Serverless Data Lake Framework.
- **Hai Lambda phân tích** (khoảng trống nội dung, từ khóa thịnh hành) với giai đoạn chất lượng dữ liệu riêng và các DLQ.
- **CI/CD thuần AWS**: một stack CodePipeline kết nối qua CodeConnections, với IAM được củng cố
  lặp đi lặp lại cho đến khi các lần deploy sạch lỗi.
- **Bảo mật cấp cột**: phân quyền Lake Formation hạn chế `user_id_hashed`, cùng một HTTP API
  cho các output phân tích.

---

👉 **Kết quả:** Đến giữa Tuần 5, pipeline OTT SDLF đã là một data lake có thể triển khai, được bảo mật,
vận hành bằng CI/CD với phân tích phục vụ qua một API.

[`637f64f`]: https://github.com/thanhtrung102/ott-sdlf/commit/637f64f
[`f9e718c`]: https://github.com/thanhtrung102/ott-sdlf/commit/f9e718c
[`8443b26`]: https://github.com/thanhtrung102/ott-sdlf/commit/8443b26
[`7dfea60`]: https://github.com/thanhtrung102/ott-sdlf/commit/7dfea60
[`4b3970f`]: https://github.com/thanhtrung102/ott-sdlf/commit/4b3970f
[`30ec606`]: https://github.com/thanhtrung102/ott-sdlf/commit/30ec606
[`39a2414`]: https://github.com/thanhtrung102/ott-sdlf/commit/39a2414
[`07faa0e`]: https://github.com/thanhtrung102/ott-sdlf/commit/07faa0e
[`6a7593f`]: https://github.com/thanhtrung102/ott-sdlf/commit/6a7593f
[`d95b4d4`]: https://github.com/thanhtrung102/ott-sdlf/commit/d95b4d4
[`888a196`]: https://github.com/thanhtrung102/ott-sdlf/commit/888a196
[`cc9a33a`]: https://github.com/thanhtrung102/ott-sdlf/commit/cc9a33a

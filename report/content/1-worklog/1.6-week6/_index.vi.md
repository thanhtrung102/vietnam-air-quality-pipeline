+++
title = "Nhật ký công việc Tuần 6"
weight = 6
chapter = false
pre = " <b> 1.6. </b> "
+++

**Dự án:** OTT SDLF data-lake pipeline ·
[ott-sdlf](https://github.com/thanhtrung102/ott-sdlf)

### Mục tiêu Tuần 6 (20–26 May 2026)

- Củng cố pipeline SDLF cho production và loại bỏ mã chết.
- Tạo ra một **FCJ workshop đã xác minh trực tiếp** trên giao diện trực quan của AWS-workshop.
- Hợp nhất bề mặt phân tích về một **dashboard** được host duy nhất.
- Audit dự án end-to-end và đề xuất một **thiết kế lại MVP** theo nguyên lý gốc.

### Công việc thực hiện trong tuần

| Ngày | Công việc | Bắt đầu | Hoàn thành | Commit |
| :-- | :--- | :--- | :--- | :--- |
| 1 | **FCJ workshop + xác minh** — củng cố production + dọn dẹp mã chết; chuyển site sang template FCJ workshop và áp dụng frontend FCJ **hugo-theme-learn** (`danielleit241/aws-fcj-report`) — chính là theme được dùng lại sau này cho báo cáo chất lượng không khí này; thêm một chương Live Verification với `verify_live.py`; kích hoạt và xác minh việc thực thi RBAC cấp cột của Lake Formation. | 20/05/2026 | 20/05/2026 | [`904b57e`] |
| 2 | **Host dashboard & sửa lỗi** — host dashboard phân tích tìm kiếm trên **S3 + CloudFront**, lấy nguồn từ tầng curated; đóng phần bàn giao bộ phân loại LUT-Refresh và thêm một cảnh báo lỗi Stage-A; tập trung hóa dashboard và sửa việc gom nhóm phân loại/từ khóa null; loại bỏ tầng gold không dùng. | 21/05/2026 | 21/05/2026 | [`3dd4a57`] |
| 3 | **Hợp nhất & khả năng tái lập** — hợp nhất về một bề mặt dashboard duy nhất (gỡ bỏ API phân tích và Lambda content-gap khi không còn dùng); đối chiếu các template CloudFormation với trạng thái stack trực tiếp để template sở hữu toàn bộ drift; sửa các lỗi tái lập workshop phát hiện trong một lượt chạy nguyên văn end-to-end; triển khai site Hugo workshop qua GitHub Actions. | 22/05/2026 | 22/05/2026 | [`b757a0d`], [`f99088c`], [`64f22b5`] |
| 4 | **Audit & thiết kế lại MVP** — rà soát toàn dự án với loại bỏ mã chết và củng cố escaping đầu vào; hiệu năng Glue (cache source DataFrame, cache+count trước khi ghi); soạn một **đề xuất thiết kế lại MVP** theo nguyên lý gốc, ưu tiên sư phạm, cùng một tài liệu ARCHITECTURE, một nhật ký quyết định và README cho cả 9 stack. | 26/05/2026 | 26/05/2026 | [`4845c89`], [`e826c4c`], [`50d87c7`] |

### Thành quả Tuần 6

- **Một workshop định dạng FCJ, đã xác minh trực tiếp** cho pipeline SDLF trên theme AWS-workshop — và là
  lần đầu tiên sử dụng frontend FCJ `hugo-theme-learn` mà báo cáo chất lượng không khí này về sau áp dụng.
- **Một dashboard duy nhất, được host** trên S3 + CloudFront, sau khi hợp nhất loại bỏ các bề mặt API/Lambda dư thừa.
- **Đối chiếu template/trực tiếp**: CloudFormation được đặt làm nguồn sự thật duy nhất cho stack đã triển khai.
- **Một lượt audit phản tư + thiết kế lại MVP**: một đề xuất theo nguyên lý gốc cho một phiên bản gọn nhẹ hơn,
  dễ dạy hơn, kèm tài liệu kiến trúc và quyết định.

---

👉 **Kết quả:** Dự án OTT SDLF kết thúc Tuần 6 ở trạng thái đã củng cố, được tài liệu hóa thành một FCJ workshop
có thể tái lập, và đi kèm một đề xuất được cân nhắc kỹ về cách xây dựng lại nó đơn giản hơn.

[`904b57e`]: https://github.com/thanhtrung102/ott-sdlf/commit/904b57e
[`3dd4a57`]: https://github.com/thanhtrung102/ott-sdlf/commit/3dd4a57
[`b757a0d`]: https://github.com/thanhtrung102/ott-sdlf/commit/b757a0d
[`f99088c`]: https://github.com/thanhtrung102/ott-sdlf/commit/f99088c
[`64f22b5`]: https://github.com/thanhtrung102/ott-sdlf/commit/64f22b5
[`4845c89`]: https://github.com/thanhtrung102/ott-sdlf/commit/4845c89
[`e826c4c`]: https://github.com/thanhtrung102/ott-sdlf/commit/e826c4c
[`50d87c7`]: https://github.com/thanhtrung102/ott-sdlf/commit/50d87c7

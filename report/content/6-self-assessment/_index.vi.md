+++
title = "Tự đánh giá"
weight = 6
chapter = false
pre = " <b> 6. </b> "
+++

Trong suốt kỳ thực tập **First Cloud Journey (FCJ)** này, tôi đã học được một tập hợp rộng các dịch vụ AWS
và — quan trọng hơn — áp dụng chúng bằng cách xây dựng bốn dự án dữ liệu thực, có thể triển khai, hoàn chỉnh end-to-end:
pipeline **Vietnam Air Quality** (sản phẩm chính được ghi lại trong báo cáo này), một pipeline **OTT Search
Analytics**, một **pipeline data-lake OTT trên Serverless Data Lake Framework (SDLF)**, và một
**OTT Data Analyst Agent dựa trên Bedrock**. Phần công việc dự án trải dài từ cuối tháng 3 đến đầu tháng 6 năm 2026.

Qua các dự án này, tôi tiến bộ nhiều nhất ở **kỹ thuật dữ liệu serverless** (S3, Glue, Athena, Kinesis, Lambda,
EventBridge), **infrastructure as code** (Terraform và CloudFormation/SDLF), **analytics engineering**
(mô hình hóa dbt, kiểm thử chất lượng dữ liệu, dự báo chuỗi thời gian), và **quản trị và bảo mật**
(truy cập cấp cột với Lake Formation, các bản rà soát Well-Architected, xử lý secrets, khả năng quan sát). Tôi cũng
học được cách tự đặt cho mình một tiêu chuẩn cao hơn về tính chính xác — kiểm chứng mọi tuyên bố được ghi lại với
tài khoản AWS thực tế thay vì dựa trên giả định của bản thân. Các phần bên dưới là sự phản ánh trung thực về
những gì tôi làm tốt và những gì tôi vẫn cần cải thiện.

### Tự đánh giá

| STT | Tiêu chí | Mô tả | Tốt | Khá | Trung bình |
| :-- | :--- | :--- | :--: | :--: | :--: |
| 1 | Kiến thức và kỹ năng chuyên môn | Thiết kế và bàn giao bốn pipeline dữ liệu AWS end-to-end (ingestion → catalog → transform → serving), với IaC, dự báo và BI. | ✅ | | |
| 2 | Khả năng học hỏi | Tiếp thu SDLF, Lake Formation, QuickSight, dbt và các Bedrock agent từ con số không và áp dụng từng thứ vào một sản phẩm hoạt động được. | ✅ | | |
| 3 | Tính chủ động | Liên tục vượt ra ngoài phạm vi MVP — thêm dự báo, củng cố Well-Architected và một harness quản trị mà không cần được yêu cầu. | ✅ | | |
| 4 | Tinh thần trách nhiệm | Kiểm chứng trực tiếp mọi chỉ số được báo cáo, củng cố bảo mật và sửa lỗi của chính mình một cách công khai (ví dụ, gỡ bỏ một trích dẫn dữ liệu bịa đặt). | ✅ | | |
| 5 | Tính kỷ luật | Bàn giao đều đặn trong từng dự án, nhưng nhịp độ tổng thể có một khoảng trống kéo dài nhiều tuần giữa các dự án mà việc lập kế hoạch ổn định hơn sẽ tránh được. | | ✅ | |
| 6 | Tinh thần cầu tiến | Thực hiện các đợt audit lặp, các lần tái lập end-to-end, và thậm chí soạn một đề xuất thiết kế lại MVP từ nguyên lý cơ bản cho một dự án. | ✅ | | |
| 7 | Giao tiếp | Tài liệu và báo cáo viết khá tốt; việc chủ động trao đổi trực tiếp với mentor là điều tôi nên làm thường xuyên hơn. | | ✅ | |
| 8 | Làm việc nhóm | Các dự án phần lớn là cá nhân, nên tôi có ít cơ hội thể hiện sự cộng tác trong môi trường nhóm. | | ✅ | |
| 9 | Tác phong chuyên nghiệp | Duy trì lịch sử git gọn gàng, báo cáo trung thực và tôn trọng các ràng buộc về chi phí và bảo mật xuyên suốt. | ✅ | | |
| 10 | Tư duy giải quyết vấn đề | Tự gỡ rối các vấn đề khó một cách độc lập — chuỗi IAM cho CI/CD, partition projection của Athena, dự báo SARIMA, timeout của Glue. | ✅ | | |
| 11 | Đóng góp cho dự án/tổ chức | Bàn giao bốn workshop FCJ có thể tái lập và một portfolio đã công bố mà người khác có thể triển khai lại từ một bản clone sạch. | ✅ | | |
| 12 | Tổng quan | Một kỳ thực tập hiệu quả với đầu ra kỹ thuật mạnh; những điểm cần phát triển chính là tính nhất quán và sự cộng tác. | ✅ | | |

### Những điểm cần cải thiện

- **Tính nhất quán và quản lý thời gian** — duy trì một nhịp độ làm việc ổn định hơn và tránh các khoảng trống dài giữa
  các dự án; lập kế hoạch các cột mốc để tiến độ diễn ra liên tục thay vì dồn dập từng đợt.
- **Giao tiếp với mentor và đồng nghiệp** — chủ động trao đổi sớm và thường xuyên hơn, thay vì dựa vào
  tài liệu để truyền tải thông điệp sau khi sự việc đã xảy ra.
- **Làm việc nhóm và cộng tác** — tìm kiếm các bối cảnh làm việc nhóm và peer review để cân bằng một kỳ thực tập
  vốn nặng về công việc dự án cá nhân.
- **Kỷ luật về phạm vi (scoping)** — kiềm chế việc over-engineering; lần thiết kế lại MVP của OTT SDLF đã dạy tôi xây dựng
  phiên bản đúng nhỏ nhất trước và chỉ bổ sung chiều sâu khi nó thực sự xứng đáng.
- **Thói quen test-first** — đưa kiểm thử và khả năng quan sát vào sớm hơn trong từng dự án thay vì bổ sung
  chúng trong giai đoạn củng cố muộn.
- **Kiểm chứng theo lĩnh vực (domain)** — xác minh các tuyên bố về lĩnh vực và khoa học với các nguồn có thẩm quyền trước
  khi bàn giao (trích dẫn PM2.5 đã được sửa mà tôi phải gỡ bỏ là một bài học tôi sẽ không lặp lại).

---

👉 **Tổng kết:** Kỳ thực tập này đã đưa tôi từ việc học các dịch vụ AWS đến việc bàn giao các hệ thống dữ liệu
chất lượng production, có thể tái lập trên cloud. Tôi tự hào về chiều sâu kỹ thuật và sự trung thực của công việc,
và tôi đã có một hình dung rõ ràng, cụ thể về cách trở thành một kỹ sư nhất quán và cộng tác hơn trong tương lai.

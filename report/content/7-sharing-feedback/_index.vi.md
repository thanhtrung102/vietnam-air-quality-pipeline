+++
title = "Chia sẻ và Phản hồi"
weight = 7
chapter = false
pre = " <b> 7. </b> "
+++

Phần này chia sẻ những suy ngẫm chân thành của tôi về kỳ thực tập **First Cloud Journey (FCJ)** — môi trường,
sự hỗ trợ tôi nhận được, công việc liên hệ thế nào với việc học của tôi, và những gì tôi muốn đề xuất để
chương trình tốt hơn nữa. Giọng điệu là trân trọng và mang tính xây dựng: tôi đã học được rất nhiều, và những ghi chú
bên dưới được đưa ra với tinh thần giúp ích cho các khóa sau.

### Đánh giá tổng quan

**1. Môi trường làm việc**

Môi trường FCJ thân thiện và thực sự hướng tới cộng đồng. Chương trình trao cho thực tập sinh quyền sở hữu thực sự
đối với các dự án thực thay vì những bài tập bỏ đi — trong kỳ thực tập này tôi đã xây dựng bốn hệ thống dữ liệu AWS
có thể triển khai một cách hoàn chỉnh end-to-end, đó là loại trách nhiệm giúp tăng tốc sự phát triển. Cộng đồng cởi mở và
sẵn lòng chia sẻ, và các câu hỏi được đáp lại bằng sự giúp đỡ thay vì sự phán xét. Nếu được đề xuất một
điểm cải thiện, đó sẽ là một chút **thời gian đồng bộ (synchronous) đều đặn, được lên lịch** (một buổi check-in cố định hàng tuần
hoặc một khối thời gian làm việc chung); phần lớn công việc của tôi diễn ra độc lập và trực tuyến, và một nhịp chung ổn định hơn
sẽ giúp việc cộng tác và phản hồi nhanh dễ dàng hơn.

**2. Hỗ trợ từ Mentor và Quản trị viên chương trình**

Sự hỗ trợ tận tâm và luôn sẵn có, thường vượt ngoài giờ tiêu chuẩn. Tôi đặc biệt trân trọng
triết lý mentoring là **chỉ cho thực tập sinh tới tài liệu và để họ tự xử lý vấn đề**
thay vì trao sẵn câu trả lời. Cách tiếp cận đó phù hợp với cách tôi học tốt nhất và thúc đẩy tôi gỡ rối các vấn đề
khó một cách độc lập — chuỗi quyền IAM cho CI/CD, partition projection của Athena, dự báo SARIMA,
timeout của Glue. Nó xây dựng sự tự tin và khả năng tự chủ thực sự mà cách "đút từng thìa" không bao giờ làm được.

**3. Mức độ liên quan của công việc với chuyên ngành học**

Kỳ thực tập đã bắc cầu giữa lý thuyết học thuật và thực hành chuyên nghiệp. Những khái niệm tôi mới chỉ thấy
trong chương trình học — mô hình hóa dữ liệu, ETL/ELT, infrastructure as code, bảo mật và kiểm soát truy cập — trở nên
cụ thể khi triển khai chúng trên AWS cho một pipeline hoạt động được. Nó củng cố các kỹ năng lập trình, DevOps và
kỹ thuật dữ liệu của tôi theo cách mà chỉ các lớp học không thể làm được, và mang lại cho tôi một portfolio tôi thực sự có thể trình bày và
triển khai lại.

**4. Cơ hội học hỏi và phát triển kỹ năng**

Bề rộng các dịch vụ tôi được áp dụng là điểm nổi bật: ingestion serverless (Kinesis, Lambda,
EventBridge), bộ công cụ phân tích (S3, Glue, Athena, dbt, QuickSight), quản trị (Lake Formation,
các bản rà soát Well-Architected), và generative AI (một agent phân tích dữ liệu dựa trên Bedrock). Cũng quý giá không kém là
các **thói quen kỹ thuật** mà chương trình củng cố — kiểm chứng mọi tuyên bố với hệ thống thực tế,
viết các workshop có thể tái lập, và tự rà soát công việc của mình một cách đối kháng trước khi coi là hoàn thành.

**5. Văn hóa công ty và tinh thần đồng đội**

Văn hóa mang tính cộng tác và hướng tới học hỏi, với sự nhấn mạnh mạnh mẽ vào **chia sẻ tri thức**. Có
một sự cân bằng lành mạnh giữa công việc độc lập, tập trung và một cộng đồng hỗ trợ để dựa vào. Sự
kỳ vọng về tính trung thực và khả năng tái lập — trình bày cách làm của bạn, chứng minh kết quả của bạn — đã định hình cách tôi nay
tiếp cận kỹ thuật nói chung.

### Suy nghĩ bổ sung và lời cảm ơn

Tôi biết ơn chương trình FCJ, các mentor và cộng đồng rộng lớn hơn vì một kỳ thực tập đã đưa tôi từ
việc học các dịch vụ AWS đến việc bàn giao các hệ thống cloud chất lượng production, có thể tái lập. Món quà lớn nhất là
**tư duy**: xây dựng những thứ thực, kiểm chứng chúng một cách trung thực, ghi lại chúng để người khác có thể làm theo. Đề xuất hướng tới
tương lai duy nhất của tôi — thêm một chút cộng tác có cấu trúc và peer review — phản chiếu chính các mục tiêu phát triển
của tôi từ phần [Tự đánh giá](../6-self-assessment/), và tôi hy vọng sẽ tiếp tục phát triển điều đó khi tôi
tiếp tục với cloud và kỹ thuật dữ liệu.

---

👉 **Cảm ơn** tới tất cả mọi người trong cộng đồng First Cloud Journey. Trải nghiệm này đã mang lại cho tôi cả
nền tảng kỹ thuật và những thói quen chuyên nghiệp mà tôi sẽ mang theo vào giai đoạn tiếp theo của sự nghiệp.

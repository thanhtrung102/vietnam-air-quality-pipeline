+++
title = "Bài viết 3"
weight = 3
chapter = false
pre = " <b> 3.3. </b> "
+++

# How BMW Group built a serverless terabyte-scale data transformation architecture with dbt and Amazon Athena

_Tóm tắt bằng tiếng Anh từ bài đăng trên AWS Big Data Blog của Philipp Karg, Cizer Pereira, và Selman Ay —
29 April 2025
([Amazon Athena](https://aws.amazon.com/blogs/big-data/category/analytics/amazon-athena/),
Amazon QuickSight, Analytics, Customer Solutions). Bài viết gốc được liên kết ở cuối trang; phần tóm tắt
dưới đây được viết bằng lời của tôi._

## Bối cảnh thiết lập

BMW Group vận hành một nền tảng phân tích lớn trên một stack chuyển đổi (transformation) hoàn toàn
**serverless**: **dbt** cung cấp logic mô hình hóa và kiểm thử, còn **Amazon Athena** là query engine thực thi
SQL. Vì Athena mở rộng theo nhu cầu và chỉ tính phí cho lượng dữ liệu mà mỗi truy vấn quét, đội ngũ không phải
vận hành cụm (cluster) nào và chỉ trả tiền cho năng lực tính toán chuyển đổi trong lúc nó thực sự chạy.

## Vì sao dùng dbt trên Athena

Việc kết hợp dbt với Athena cho phép các kỹ sư biểu diễn các phép chuyển đổi dưới dạng các SQL model được quản lý
phiên bản (version-controlled), trong khi nền tảng đảm nhận việc thực thi và mở rộng. Hiệu quả của Athena trên các
tập dữ liệu Parquet lớn, kết hợp với mô hình tính phí serverless của nó, có nghĩa là đội ngũ có thể tập trung vào
việc viết các phép chuyển đổi tốt thay vì định cỡ và chăm sóc hạ tầng.

## Kiến trúc model phân lớp

Bài viết mô tả khoảng **400 dbt model** được tổ chức thành ba giai đoạn:

- **Source** — dữ liệu thô như khi được nạp vào.
- **Prepared** — các bảng đã được làm sạch và chuẩn hóa.
- **Semantic** — các tập tổng hợp sẵn sàng cho nghiệp vụ, được tiêu thụ bởi analytics và BI.

Cách phân lớp này giữ cho mỗi phép chuyển đổi nhỏ gọn và có thể kết hợp (composable), đồng thời giúp dễ dàng theo
dõi lineage từ dữ liệu đầu vào thô đến đầu ra nghiệp vụ.

## Xử lý incremental

Thay vì xây dựng lại toàn bộ tập dữ liệu trong mỗi lần chạy, các dbt model chỉ xử lý **dữ liệu mới hoặc đã thay
đổi** theo kiểu incremental. Điều đó giảm mạnh cả khối lượng dữ liệu được xử lý lẫn chi phí scan của Athena, và
đó chính là điều khiến cách tiếp cận này khả thi về chi phí ở quy mô terabyte.

## Cô lập bằng workgroup

Các kiểu truy vấn khác nhau — chuyển đổi, kiểm thử, BI/trực quan hóa, và phân tích ad-hoc — được chạy trong các
**Athena workgroup riêng biệt**. Việc cô lập chúng cho phép phân bổ chi phí và quản trị theo từng workgroup, nên
mức chi tiêu và cấu hình của mỗi workload có thể được quản lý độc lập.

## CI/CD và chất lượng dữ liệu

Việc triển khai được tự động hóa thông qua **GitHub Actions**, được kích hoạt từ các pull request, với các thay
đổi schema được quản lý qua cấu hình dbt thay vì DDL viết tay. Các **test** tích hợp sẵn của dbt tự động kiểm
chứng các ràng buộc schema, tính toàn vẹn tham chiếu (referential integrity), và các quy tắc nghiệp vụ tùy chỉnh
trên mỗi pull request cũng như trong các bản build hằng đêm — nhờ vậy các hồi quy về chất lượng dữ liệu được phát
hiện trước khi chúng đến tay người tiêu dùng.

## Sự đánh đổi về chi phí

Một bài học đáng chú ý: việc chuyển từ các **view** phức tạp, bị tính toán lại nhiều lần sang các bảng semantic đã
được **materialise** đã loại bỏ phần tính toán dư thừa và tạo ra mức giảm chi phí ròng, dù nó làm tăng tổng khối
lượng công việc dbt. Việc materialise lớp semantic đánh đổi một chút chi phí build tăng thêm để có các lần đọc rẻ
hơn và nhanh hơn nhiều ở hạ nguồn.

## Áp dụng trong dự án này

Pipeline Vietnam Air Quality chính là kiến trúc đó ở quy mô thực tập. Nó chạy
**dbt-athena-community** trên `openaq_workgroup` (với **trần scan 10 GB mỗi truy vấn**) và tổ chức
**17 model** thành cùng loại các lớp mà BMW sử dụng: **staging → intermediate → marts**
(ánh xạ tới Source → Prepared → Semantic). Bản build mặc định là **13 trên 17** mart
(`--exclude tag:bi_disabled`), và bộ kiểm thử mang theo **84 test** — các kiểm tra generic, singular freshness
và invariant, hai **unit test** cho phép toán breakpoint AQI theo EPA-2024, và các kiểm tra phạm vi (range) bằng
dbt-expectations. Điểm thay thế duy nhất: thay vì GitHub Actions, một project **AWS CodeBuild**
(`openaq-dbt-runner`) chạy dbt theo lịch hằng ngày, được đóng gói lại trên mỗi lần `terraform apply`. Các mart là
các bảng đã materialise được hàm `aqi_api` Lambda đọc — chính lựa chọn "materialise lớp semantic" mà bài viết
khuyến nghị vì lý do chi phí.

**Nguồn:** [How BMW Group built a serverless terabyte-scale data transformation architecture with dbt and Amazon Athena](https://aws.amazon.com/blogs/big-data/how-bmw-group-built-a-serverless-terabyte-scale-data-transformation-architecture-with-dbt-and-amazon-athena/).

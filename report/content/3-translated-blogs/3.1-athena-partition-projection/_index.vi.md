+++
title = "Blog 1"
weight = 1
chapter = false
pre = " <b> 3.1. </b> "
+++

# Speed up your Amazon Athena queries using partition projection

_Tóm tắt bằng tiếng Anh từ bài viết trên AWS Big Data Blog của Steven Wasserman, Janak Agarwal, Juan
Lamadrid, và Pathik Shah — 19 May 2021
([Amazon Athena](https://aws.amazon.com/blogs/big-data/category/analytics/amazon-athena/), Analytics).
Bài gốc được liên kết ở cuối; phần trình bày dưới đây là theo lời văn của riêng tôi._

## Bài toán: tra cứu metadata trên các bảng có nhiều phân vùng

Amazon Athena truy vấn dữ liệu trong Amazon S3 và sử dụng AWS Glue Data Catalog (hoặc một Hive metastore) để biết
những phân vùng nào tồn tại và chúng nằm ở đâu. Đối với một bảng chỉ có vài phân vùng, việc này
rẻ. Nhưng khi một bảng phát triển lên hàng nghìn hoặc hàng chục nghìn phân vùng — phổ biến với dữ liệu
được phân vùng theo year/month/day/hour — Athena phải lấy về và lọc toàn bộ metadata phân vùng đó từ
catalog trước khi có thể đọc được dù chỉ một byte dữ liệu. Bước truy xuất metadata từ xa đó trở thành chi phí
chủ đạo của truy vấn, và nó càng chậm hơn khi càng nhiều phân vùng tích lũy.

## Cách partition projection hoạt động

Partition projection loại bỏ vòng truy xuất tới catalog. Thay vì tra cứu phân vùng, bạn mô tả
chúng một lần trong các thuộc tính của bảng, và Athena **tính toán** các giá trị phân vùng cùng vị trí S3 của
chúng trong bộ nhớ tại thời điểm truy vấn. Khi một truy vấn có mệnh đề `WHERE` trên các cột phân vùng, Athena
chỉ chiếu (project) những phân vùng khớp — nó không bao giờ liệt kê toàn bộ catalog. Vì việc sinh giá trị trong bộ nhớ
nhanh hơn nhiều so với một lệnh gọi metadata từ xa, các truy vấn trên những bảng có nhiều phân vùng được tăng tốc,
và những phân vùng mới đến có thể truy vấn ngay lập tức mà không cần `ALTER TABLE … ADD PARTITION` hay chạy
một crawler.

## Các loại projection

Bạn cấu hình projection cho từng cột phân vùng. Bài viết mô tả các loại sau:

- **`enum`** — một danh sách giá trị cố định (ví dụ một tập nhỏ các region hoặc station ID).
- **`integer`** — một dải số, có thể tùy chọn độ rộng chữ số cố định.
- **`date`** — một dải ngày/giờ với một định dạng và một khoảng (interval); dải có thể là tương đối, chẳng hạn bắt đầu
  từ `2013-10-01` đến `NOW`, rất phù hợp cho dữ liệu chuỗi thời gian liên tục tăng trưởng.
- **`injected`** — các giá trị không do Athena sinh ra mà được cung cấp trực tiếp trong mệnh đề `WHERE` của truy vấn,
  dành cho các khóa có lực lượng (cardinality) cao không thể liệt kê được.

Một bảng phân vùng theo ngày điển hình sẽ đặt các thuộc tính bảng theo kiểu
`projection.enabled = true`, một `projection.<col>.type`, các thiết lập range/format/interval, và một
`storage.location.template` ánh xạ mỗi giá trị được chiếu tới prefix S3 của nó.

## Hiệu năng và chi phí

Bài viết báo cáo một ví dụ khách hàng (Vertex) trong đó projection rút ngắn một truy vấn production từ 137 giây
xuống còn khoảng 10 giây (~92%) và giảm báo cáo batch cuối tháng từ khoảng 4.5 giờ xuống còn 40 phút
(~85%). Vì projection cho phép Athena cắt tỉa xuống đúng những prefix cần thiết — và kết hợp tự nhiên
với các định dạng dạng cột, nén như Parquet — khối lượng dữ liệu được quét cũng giảm theo, điều này trực tiếp hạ
chi phí trên mỗi truy vấn của Athena.

## Khi nào dùng nó, và hạn chế chính

Partition projection là công cụ phù hợp khi một bảng có nhiều phân vùng, khi các phân vùng date/time mới
xuất hiện theo lịch, hoặc khi việc giữ cho catalog đồng bộ vốn dĩ là một việc nhọc nhằn. Hạn chế
then chốt: các phân vùng được chiếu **chỉ được hiểu bởi Athena**. Các engine khác đọc cùng
bảng đó (Redshift Spectrum, EMR) vẫn dựa vào metadata phân vùng thông thường trong catalog.

## Áp dụng trong dự án này

Pipeline Vietnam Air Quality lập danh mục **ba bảng ngoại (external table) thô** — `batch`, `stream`, và
`weather` — và mỗi bảng trong số đó đều dùng **partition projection trên các khóa date/time**, nên **không có Glue
crawler nào từng chạy** và không có chi phí crawl trên mỗi lần quét. Các object mới theo ngày và theo giờ đáp xuống S3 dưới
các prefix kiểu Hive và trở nên có thể truy vấn ngay lập tức, không có gì phải đăng ký. Kết hợp với
**giới hạn quét 10 GB trên mỗi truy vấn** của `openaq_workgroup`, projection là một phần lớn lý do vì sao toàn bộ pipeline
nằm trong khoảng chi phí ~$3–8/tháng của nó. Các object streaming mà projection đọc được tạo ra bởi
luồng Firehose mô tả trong [Blog 2](../3.2-firehose-dynamic-partitioning/).

**Source:** [Speed up your Amazon Athena queries using partition projection](https://aws.amazon.com/blogs/big-data/speed-up-your-amazon-athena-queries-using-partition-projection/) ·
tài liệu tham khảo: [Use partition projection with Amazon Athena](https://docs.aws.amazon.com/athena/latest/ug/partition-projection.html).

+++
title = "Bài viết 2"
weight = 2
chapter = false
pre = " <b> 3.2. </b> "
+++

# Amazon Data Firehose now supports dynamic partitioning to Amazon S3

_Tóm tắt bằng tiếng Anh từ bài đăng trên AWS Big Data Blog của Jeremy Ber và Michael Greenshtein —
2 September 2021 (Analytics, Kinesis Data Firehose). Bài viết gốc được liên kết ở cuối trang; phần tóm tắt
dưới đây được viết bằng lời của tôi._

## Bối cảnh: đưa dữ liệu streaming vào một bố cục thân thiện với truy vấn

Amazon Data Firehose (trước đây là Kinesis Data Firehose) là cách được quản lý để nạp dữ liệu streaming vào
data lake — nó đệm (buffer) các bản ghi đến và chuyển chúng tới Amazon S3 (cùng các đích khác) mà không cần
vận hành máy chủ nào. Trước đây, Firehose ghi các đối tượng theo một prefix mặc định dựa trên thời gian, được
suy ra từ thời điểm chuyển giao. Cách đó vẫn hoạt động, nhưng những đội muốn dữ liệu được bố trí theo một thuộc
tính *bên trong* bản ghi (khách hàng, thiết bị, ngày sự kiện) thường phải chạy thêm một job thứ hai để
repartition dữ liệu sau khi nó được ghi xuống, làm tăng độ trễ và chi phí.

## Dynamic partitioning bổ sung điều gì

Dynamic partitioning cho phép Firehose nhóm các bản ghi vào các prefix S3 đã được phân vùng **ngay khi chuyển
giao**, dựa trên các giá trị mà nó trích xuất từ mỗi bản ghi. Bạn định nghĩa cách các partition key được suy ra
và một mẫu prefix (prefix template) để đặt mỗi bản ghi vào đúng đường dẫn S3 — nhờ vậy dữ liệu đã sẵn sàng cho
truy vấn ngay khi đến, không cần bước hậu xử lý.

## Suy ra partition key

Bài viết mô tả hai cách để thu được partition key:

- **Phân tích nội dòng (inline parsing) với jq** — đối với các bản ghi JSON, bạn chọn các trường (bao gồm cả các
  trường lồng nhau) bằng các biểu thức jq, và Firehose dùng những giá trị đó làm partition key.
- **Một Lambda transform** — đối với payload không phải JSON, đã nén hoặc đã mã hóa, một hàm AWS Lambda có thể
  giải mã bản ghi và trả về metadata phân vùng mà Firehose nên sử dụng.

Các key có thể được kết hợp thành các bố cục nhiều cấp — ví dụ phân vùng theo một định danh, rồi theo loại thiết
bị, rồi theo đường dẫn `year/month/day/` suy ra từ timestamp — để khớp với cách các nhà phân tích sẽ lọc dữ liệu.

## Buffering và chuyển giao

Firehose duy trì một **buffer riêng cho mỗi partition đang hoạt động**. Ngưỡng buffer cho dynamic partitioning
dao động khoảng **64–128 MiB** về kích thước và **1–15 phút** về thời gian; ngưỡng nào đạt trước sẽ kích hoạt
việc chuyển giao buffer của partition đó tới S3.

## Giới hạn và xử lý lỗi

Có một giới hạn mềm (soft limit) khoảng **500 active partition** trên mỗi delivery stream (có thể nâng qua
Support) và một trần thông lượng (throughput) trên mỗi partition. Các bản ghi mà không thể tính được partition
key — chẳng hạn do thiếu một trường — sẽ được định tuyến tới một **error prefix** chuyên dụng trong S3 thay vì
bị loại bỏ, nên không có gì bị mất một cách âm thầm.

## Vì sao điều này quan trọng ở phía hạ nguồn

Vì dữ liệu được ghi xuống đã được phân vùng sẵn, các query engine như Athena và Redshift Spectrum có thể cắt tỉa
(prune) xuống chỉ các prefix liên quan (partition pruning), giúp cải thiện hiệu năng truy vấn và giảm chi phí —
chính lợi ích đã được đề cập trong [Blog 1](../3.1-athena-partition-projection/).

## Áp dụng trong dự án này

Đường đi gần thời gian thực (near-real-time) của pipeline là `streaming_producer` (Lambda, mỗi 30 phút) →
**Kinesis Data Streams** (ON_DEMAND, KMS) → **Amazon Data Firehose** → `raw/stream/`. Firehose đệm dữ liệu
với **nén GZIP và buffer 128 MB / 300 s**, ghi các đối tượng theo bố cục dựa trên thời gian
`raw/stream/yyyy/MM/dd/HH/` — chính ý tưởng "phân vùng ngay trên đường vào" mà bài viết này giới thiệu. Dự án
cố ý sử dụng phân vùng **timestamp-namespace** của Firehose thay vì các jq dynamic key, vì bảng Glue ở hạ nguồn
đọc các prefix đó thông qua **partition projection** (Blog 1), nên dữ liệu streaming có thể truy vấn được trong
Athena ngay khoảnh khắc nó được ghi xuống — không cần crawler, không cần job repartition. Các lỗi bất đồng bộ
(async) được bắt lại bởi SQS queue `openaq_streaming_dlq`, phản chiếu lại tấm lưới an toàn error-prefix mà bài
viết đề cập.

**Nguồn:** [Amazon Data Firehose now supports dynamic partitioning to Amazon S3](https://aws.amazon.com/blogs/big-data/kinesis-data-firehose-now-supports-dynamic-partitioning-to-amazon-s3/).

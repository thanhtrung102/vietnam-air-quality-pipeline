+++
title = "Đề xuất dự án"
weight = 2
chapter = false
pre = " <b> 2. </b> "
+++


## 2.1 Bài toán kinh doanh

Việt Nam — đặc biệt là Hà Nội — có một trong những mức PM2.5 cao nhất Đông Nam Á, thường xuyên vượt
ngưỡng hướng dẫn 24 giờ của WHO (15 µg/m³) và tiêu chuẩn quốc gia QCVN 05:2023. Dữ liệu chất lượng không khí
công khai cho các trạm tại Việt Nam đã tồn tại (OpenAQ), nhưng ở dạng thô, theo từng trạm và chưa sẵn sàng
để phân tích: chưa có một góc nhìn hợp nhất, hướng tới sức khỏe nào kết hợp số đo chất ô nhiễm với khí tượng,
áp dụng phương pháp luận AQI hiện hành của US EPA, theo dõi mức độ tuân thủ theo thời gian, hay dự báo tuần
tới.

Dự án này là một **portfolio/demo AWS First Cloud Journey (FCJ)**. Mục tiêu của nó có tính kép:

1. **Chứng minh năng lực kỹ thuật dữ liệu serverless** trên AWS (mục tiêu đánh giá FCJ); và
2. Sử dụng một **câu chuyện thực tế, có ý nghĩa** — phân tích PM2.5 của Việt Nam — làm phương tiện truyền tải.

Đây là một bản demo, không phải dịch vụ công được cấp ngân sách: không có SLA cho người dùng thực và không có
bên tiêu thụ mang tính quy định. Phạm vi giới hạn ở 21 trạm OpenAQ trong danh sách.

## 2.2 Mục tiêu

- Thu nạp dữ liệu chất lượng không khí lịch sử **và** gần thời gian thực cho 21 trạm tại Việt Nam, cùng các biến khí tượng ERA5.
- Chuyển đổi dữ liệu thành các mart sẵn sàng phân tích, đã được kiểm thử, sử dụng các ngưỡng **US EPA 2024 AQI** hiện hành.
- Cung cấp một **bản đồ trạm trực tiếp** và một **dashboard phân tích** (bảng điểm sức khỏe, các yếu tố tác động theo mùa/thời tiết,
  mức tuân thủ WHO/QCVN, và một **dự báo PM2.5 7 ngày**).
- Giữ mọi thứ **serverless, tái lập được (Terraform), và trong khoảng chi phí ~$3–8/tháng**.

## 2.3 Kiến trúc mục tiêu

Ba luồng thu nạp song song hội tụ về một data lake trên S3, được lập danh mục bởi Glue (partition projection),
chuyển đổi bởi **dbt-on-Athena** (chạy bởi CodeBuild), và phục vụ qua một API + dashboard tĩnh, với một
bộ dự báo SARIMA dạng container-Lambda. *(Các thông tin trong sơ đồ đã được đối chiếu với trạng thái thực tế 2026-06-01; phiên bản
dùng biểu tượng AWS được sinh ra từ `docs/architecture.yaml` qua awslabs diagram-as-code.)*

{{< mermaid >}}
flowchart LR
  subgraph EXT[External sources]
    A1[OpenAQ S3 Archive]:::ext
    A2[OpenAQ REST API v3]:::ext
    A3[Open-Meteo ERA5]:::ext
  end

  subgraph AWS[AWS Cloud · ap-southeast-1 · no VPC]
    EB[EventBridge Scheduler<br/>6 schedules]:::sched
    SM[Secrets Manager<br/>openaq/api_key]:::sched

    L1[batch_sync<br/>Lambda]:::lam
    L2[streaming_producer<br/>Lambda]:::lam
    L3[weather_ingest<br/>Lambda]:::lam

    KIN[Kinesis + Firehose]:::strm
    S3[(S3 data lake<br/>batch · stream · weather)]:::stor
    GL[Glue Data Catalog<br/>partition projection]:::glue
    ATH[Athena<br/>openaq_workgroup]:::ath
    CB[CodeBuild · dbt<br/>17 models · 84 tests]:::cb

    API[aqi_api + API Gateway<br/>GeoJSON]:::api
    FC[forecast_generate<br/>SARIMA 7-day]:::lam
    DASH[(S3 static site<br/>map + analytics)]:::stor
    CK[completeness_check]:::lam
    CW[CloudWatch · 14 alarms<br/>+ AWS Budget]:::mon
  end
  USER([End user · browser]):::ext

  A1 --> L1
  A2 --> L2
  A3 --> L3
  EB -.-> L1 & L2 & L3 & CB & FC & CK
  SM -.-> L2
  L1 --> S3
  L3 --> S3
  L2 --> KIN --> S3
  S3 --> GL --> ATH
  ATH <--> CB
  ATH --> API
  ATH --> FC
  API --> DASH --> USER
  FC --> CW
  CK --> CW

  classDef ext fill:#e8edf3,stroke:#566,stroke-width:1px,color:#16191f;
  classDef lam fill:#FF9900,stroke:#cc7a00,color:#16191f;
  classDef stor fill:#3F8624,stroke:#2d6019,color:#fff;
  classDef strm fill:#8C4FFF,stroke:#6b3fcc,color:#fff;
  classDef glue fill:#8C4FFF,stroke:#6b3fcc,color:#fff;
  classDef ath fill:#146EB4,stroke:#0f5288,color:#fff;
  classDef cb fill:#146EB4,stroke:#0f5288,color:#fff;
  classDef api fill:#E7157B,stroke:#b51060,color:#fff;
  classDef sched fill:#FF4F8B,stroke:#cc3f6f,color:#fff;
  classDef mon fill:#E7157B,stroke:#b51060,color:#fff;
{{< /mermaid >}}

## 2.4 Các dịch vụ AWS được sử dụng

| Lớp | Dịch vụ | Vai trò |
|---|---|---|
| Điều phối | **EventBridge Scheduler** | 6 lịch điều khiển mọi job (scale-to-zero, không cần máy chủ) |
| Thu nạp | **Lambda** (×3, arm64) | batch_sync, streaming_producer, weather_ingest |
| Streaming | **Kinesis Data Streams + Firehose** | API gần thời gian thực → S3 (`raw/stream/`) |
| Lưu trữ | **S3** | data lake thô, mart đã xử lý, website tĩnh; lifecycle + Intelligent-Tiering |
| Danh mục | **Glue Data Catalog** | partition projection (không dùng crawler) |
| Truy vấn/Chuyển đổi | **Athena + dbt** (CodeBuild) | 17 model dbt, AQI EPA-2024, 84 test |
| Phục vụ | **API Gateway + Lambda** | bản đồ GeoJSON + JSON `/analytics/*` |
| ML | **Lambda (ECR container)** | dự báo PM2.5 SARIMA 7 ngày |
| Bí mật | **Secrets Manager** | API key OpenAQ (không lưu plaintext) |
| Độ tin cậy | **SQS** DLQ | dead-letter cho streaming + batch |
| Khả năng quan sát | **CloudWatch + SNS** | 14 alarm; **AWS Budget** ($8) |
| Trạng thái | **S3 remote backend** | có versioning + SSE, lockfile gốc (không dùng DynamoDB) |

## 2.5 Nguồn dữ liệu

- **OpenAQ** — kho lưu trữ lịch sử trên S3 (CSV.GZ, `us-east-1`) + REST API v3, 21 trạm tại Việt Nam (17 khu vực Hà Nội,
  4 TP.HCM). Giá trị sentinel `-999` được lọc bỏ; PM2.5 bị giới hạn ở 500 µg/m³ trong giai đoạn staging.
- **Open-Meteo ERA5** reanalysis — các biến khí tượng theo ngày (nhiệt độ, độ ẩm tương đối, gió, lượng mưa, chiều cao PBL).

## 2.6 Chi phí & region

- **Region:** `ap-southeast-1` (Singapore). **Chi phí:** ≈ **$3.22/tháng** (ước tính) — được kiểm soát bởi giới hạn quét
  Athena 10 GB, serverless scale-to-zero, phân tầng lưu trữ, và một AWS Budget ở mức $8.

## 2.7 Tiêu chí thành công

1. Pipeline end-to-end hoạt động trực tiếp: thu nạp → danh mục → mart → API → dashboard, với dữ liệu hiện hành.
2. AQI EPA-2024 chính xác (được kiểm chứng tự động bằng **unit test** của dbt).
3. Dự báo SARIMA 7 ngày hoạt động trực tiếp với giám sát RMSE.
4. Tái lập hoàn toàn được từ `terraform apply` (đã kiểm chứng từ một bản clone mới).
5. Well-Architected: không còn rủi ro cao nào để mở; nằm trong khoảng chi phí dự kiến.

Cả năm tiêu chí đều được đáp ứng và kiểm chứng trực tiếp (xem [Workshop]({{% relref "/5-workshop" %}}) để biết quy trình build tái lập được).

## 2.8 Khả năng tái lập & hồ sơ dự án

Quá trình build có thể tái lập end-to-end (Terraform + một runbook workshop từng bước) và quy trình
kỹ thuật được ghi lại trong repository:

- **Kiến trúc & thiết kế:** `docs/PIPELINE-REPORT.md`, `docs/architecture.yaml` (nguồn sơ đồ dùng biểu tượng AWS).
- **Luồng dữ liệu & quản trị:** `docs/DATA-LIFECYCLE.md`; **chiến lược kiểm thử:** `docs/DATA-QUALITY.md`.
- **Đánh giá Well-Architected:** `docs/WELL-ARCHITECTED.md`; **danh mục đã triển khai:** `docs/DEPLOYED-SPECS-AND-AUDIT.md`.
- **Hồ sơ tiến độ:** `process/features/fcj-portfolio-hardening/` (kế hoạch tổng, các quyết định theo phase, báo cáo
  sprint) và `process/general-plans/completed/`.

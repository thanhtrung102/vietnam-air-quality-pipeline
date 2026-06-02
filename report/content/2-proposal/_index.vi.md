+++
title = "Đề xuất dự án"
weight = 2
chapter = false
pre = " <b> 2. </b> "
+++

## 1. Tóm tắt tổng quan

**Vietnam Air Quality Pipeline** là một nền tảng dữ liệu hoàn toàn serverless trên AWS, biến các số đo
chất lượng không khí thô ở cấp trạm quan trắc thành một sản phẩm sẵn sàng phân tích, hướng đến sức khỏe:
bản đồ trạm trực tiếp với chỉ số **US EPA 2024 AQI** hiện tại, một dashboard phân tích (thẻ điểm sức khỏe,
yếu tố tác động theo mùa/thời tiết, mức độ tuân thủ WHO/QCVN), và **dự báo PM2.5 7 ngày**. Đây là một dự án
trong danh mục **AWS First Cloud Journey (FCJ)** với mục tiêu kép — minh họa kỹ thuật dữ liệu serverless cấp
độ production trên AWS, sử dụng một câu chuyện thực tế và có ý nghĩa (phân tích PM2.5 tại Việt Nam) làm phương
tiện. Mọi thứ đều có thể tái lập từ `terraform apply` và vận hành trong khung chi phí **≈ $3–8/tháng**.

## 2. Phát biểu bài toán

### 2.1 Vấn đề hiện tại

Việt Nam — đặc biệt là Hà Nội — có một trong những mức PM2.5 cao nhất Đông Nam Á, thường xuyên vượt
ngưỡng khuyến cáo 24 giờ của WHO (15 µg/m³) và tiêu chuẩn quốc gia QCVN 05:2023. Dữ liệu chất lượng không khí
công khai cho các trạm tại Việt Nam đã tồn tại (OpenAQ), nhưng nó **ở dạng thô, cấp trạm và chưa sẵn sàng để
phân tích**: chưa có một góc nhìn hợp nhất, hướng đến sức khỏe, kết hợp số đo chất ô nhiễm với khí tượng, áp
dụng phương pháp luận US EPA AQI hiện hành, theo dõi mức độ tuân thủ theo thời gian, hay dự báo cho tuần tới.

### 2.2 Giải pháp

Một pipeline serverless trên AWS thu nạp dữ liệu chất lượng không khí lịch sử **và** gần thời gian thực cùng
các biến đồng hành thời tiết ERA5, lập danh mục trên data lake S3 (Glue partition projection), biến đổi bằng
**dbt-on-Athena** thành các mart đã được kiểm thử dựa trên các breakpoint AQI EPA-2024, rồi phục vụ bản đồ
trực tiếp + dashboard phân tích và một dự báo SARIMA. Không có máy chủ nào cần quản lý: **EventBridge
Scheduler** điều khiển mọi tác vụ và toàn bộ stack co lại bằng không giữa các lần chạy.

### 2.3 Lợi ích và Giá trị

- **Thông tin hướng đến sức khỏe**, không phải con số thô: các hạng mục AQI, cách diễn giải tương đương số
  điếu thuốc lá, và mức độ tuân thủ WHO/QCVN theo thời gian.
- **Tái lập & di động**: một lệnh `terraform apply` dựng lại toàn bộ stack từ một bản clone sạch.
- **Tiết kiệm chi phí**: ≈ $3.22/tháng, được bảo vệ bởi giới hạn quét Athena 10 GB, kiến trúc serverless co
  về không, và một AWS Budget ở mức $8.
- **Chứng minh năng lực** trên toàn bộ vòng đời dữ liệu AWS (thu nạp → lập danh mục → biến đổi → phục vụ →
  dự báo → giám sát), vốn là mục tiêu đánh giá của FCJ.

## 3. Kiến trúc giải pháp

Ba luồng thu nạp song song hội tụ tại một data lake S3, được Glue lập danh mục (partition projection), được
**dbt-on-Athena** biến đổi (chạy bởi CodeBuild), và được phục vụ qua một API + dashboard tĩnh, cùng một bộ dự
báo SARIMA dạng container-Lambda. *(Các dữ kiện được kiểm chứng trực tiếp với AWS; sơ đồ biểu tượng AWS được
sinh ra từ `docs/architecture.yaml` qua awslabs diagram-as-code và được tạo lại trong CI khi deploy.)*

![AWS architecture](/vietnam-air-quality-pipeline/images/architecture.png)

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
    CW[CloudWatch · 15 alarms<br/>+ AWS Budget]:::mon
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

**Các dịch vụ AWS sử dụng**

| Tầng | Dịch vụ AWS | Vai trò |
|---|---|---|
| Điều phối | **EventBridge Scheduler** | 6 lịch điều khiển mọi tác vụ (co về không, không máy chủ) |
| Thu nạp | **Lambda** (×3, arm64) | `batch_sync`, `streaming_producer`, `weather_ingest` |
| Streaming | **Kinesis Data Streams + Firehose** | API gần thời gian thực → S3 (`raw/stream/`) |
| Lưu trữ | **S3** | data lake thô, các mart đã xử lý, website tĩnh; lifecycle + Intelligent-Tiering |
| Danh mục | **Glue Data Catalog** | partition projection (không cần crawler) |
| Truy vấn/Biến đổi | **Athena + dbt** (CodeBuild) | 17 dbt model, AQI EPA-2024, 84 test |
| Phục vụ | **API Gateway + Lambda** | bản đồ GeoJSON + JSON `/analytics/*` |
| ML | **Lambda (ECR container)** | dự báo PM2.5 SARIMA 7 ngày |
| Bí mật | **Secrets Manager** | khóa API OpenAQ (không lưu dạng văn bản thuần) |
| Độ tin cậy | **SQS** DLQ | dead-letter cho streaming + batch |
| Giám sát | **CloudWatch + SNS** | 15 alarm + một billing alarm; **AWS Budget** ($8) |
| Trạng thái | **S3 remote backend** | có version + SSE, lockfile native (không dùng DynamoDB) |

**Nguồn dữ liệu**

- **OpenAQ** — kho lưu trữ lịch sử trên S3 (CSV.GZ, `us-east-1`) + REST API v3, **21 trạm VN** (17 thuộc
  khu vực Hà Nội, 4 tại HCMC; hiện có 5 trạm đang hoạt động). Giá trị sentinel `-999` được lọc bỏ; PM2.5
  được giới hạn ở 500 µg/m³ trong tầng staging.
- **Open-Meteo ERA5** reanalysis — các biến đồng hành thời tiết hàng ngày (nhiệt độ, RH, gió, lượng mưa,
  độ cao PBL). Cả hai API đều miễn phí.

## 4. Triển khai kỹ thuật

### 4.1 Các giai đoạn triển khai

| Giai đoạn | Trọng tâm | Kết quả |
|---|---|---|
| 0–1 | Nền tảng & lát cắt đầu tiên | Terraform IaC, ba luồng thu nạp, partition projection, các dbt mart đầu tiên, bản đồ trực tiếp + API |
| 2–3 | Chất lượng dữ liệu & chẩn đoán | cờ đánh dấu giá trị ngoại lai/lệch cảm biến, các khoảng trống độ tin cậy theo IoT-Lens, các mart chẩn đoán |
| 3–5 | Thời tiết & dự báo | các biến đồng hành ERA5, kỹ thuật đặc trưng, dự báo SARIMA 7 ngày (container Lambda) |
| 6–7 | BI, kiểm chứng & Well-Architected | dashboard QuickSight/tĩnh, kiểm chứng workshop, arm64/X-Ray, mở rộng ngữ cảnh |
| 8–9 | Gia cố & quản trị | bí mật, DLQ, SSE, các alarm giám sát, remote state, bộ khung quản trị RIPER-5 |
| 10 | Tái lập & báo cáo | khả năng tái lập từ bản clone sạch, định khung kinh doanh, báo cáo FCJ này |

### 4.2 Yêu cầu kỹ thuật chi tiết

- **Thu nạp** — 3 Lambda arm64 (python3.12): `batch_sync` (hàng ngày, kho OpenAQ → `raw/batch/`),
  `streaming_producer` (30 phút, REST API v3 → Kinesis → Firehose → `raw/stream/`), `weather_ingest`
  (hàng ngày, ERA5 → `raw/weather/`). DLQ trên các luồng bất đồng bộ; khóa OpenAQ được đọc từ Secrets Manager.
- **Biến đổi** — dbt-athena-community trên CodeBuild dựng 2 staging + 2 intermediate + 13 mart (tổng 17;
  bản build mặc định loại trừ 4 mart chẩn đoán `bi_disabled`). AQI dùng các breakpoint PM2.5/PM10
  **EPA-2024** với nội suy tuyến tính từng đoạn; AQI tổng hợp = chất ô nhiễm tệ nhất.
- **Phục vụ** — Lambda `aqi_api` đứng sau API Gateway (`GET /` GeoJSON, JSON `/analytics/{health,seasonal,
  compliance,forecast}`); một **dashboard tĩnh** Leaflet + Chart.js trên website S3.
- **ML** — `forecast_generate` (container Lambda ECR) khớp SARIMA(1,1,1)(1,0,1,7) cho mỗi trạm đang hoạt
  động, ghi `mart_daily_forecast` (35 dòng / 5 trạm / 7 ngày) và phát holdout-RMSE lên CloudWatch.
- **Bảo mật** — Secrets Manager (không lưu khóa dạng văn bản thuần), IAM theo nguyên tắc đặc quyền tối
  thiểu, throttling API Gateway + reserved concurrency, truy cập công khai S3 chỉ giới hạn ở `dashboard/*`.

## 5. Lộ trình & Cột mốc (Sprint)

| Sprint | Thời gian | Cột mốc |
|---|---|---|
| 1 | Wk 1 (25–29 Mar) | Nền tảng + lát cắt đầu cuối đầu tiên (thu nạp → danh mục → mart → API → bản đồ) |
| 2 | Wk 2 (30 Mar–8 Apr) | Chất lượng dữ liệu, thời tiết ERA5, dự báo SARIMA, cấu trúc tài liệu FCJ |
| 3 | Wk 3 (9–18 Apr) | Tầng BI, kiểm chứng workshop, rà soát Well-Architected |
| 4 | Wk 7 (29–31 May) | Gia cố bảo mật/giám sát, bộ khung quản trị, remote state |
| 5 | Wk 8 (1–2 Jun) | Tái lập, định khung kinh doanh, báo cáo FCJ, kiểm chứng đầu cuối trực tiếp |

*(Chi tiết đầy đủ theo từng tuần trong [Worklog]({{% relref "/1-worklog" %}}). Các tuần 4–6 dành cho các dự
án dữ liệu OTT song song; xem trang giới thiệu worklog.)*

## 6. Ước tính chi phí

**Các dịch vụ AWS (ước tính, trạng thái ổn định)**

| Dịch vụ AWS | Thành phần / Sử dụng | Chi phí (USD/tháng) |
|---|---|---|
| Amazon S3 | data lake + website tĩnh (~vài GB, Intelligent-Tiering, lifecycle) | 0.25 |
| Amazon Athena | các bản build dbt + truy vấn API (giới hạn quét 10 GB mỗi truy vấn) | 0.70 |
| AWS Lambda | 6 hàm, arm64, co về không | 0.10 |
| Kinesis Data Streams + Firehose | on-demand, lưu lượng thấp | 0.55 |
| AWS CodeBuild | chạy dbt hàng ngày (~3–5 phút) | 0.35 |
| Amazon CloudWatch + SNS | 15 alarm, logs, dashboard | 0.45 |
| Amazon API Gateway | HTTP API, lưu lượng thấp | 0.05 |
| AWS Secrets Manager | 1 bí mật | 0.40 |
| Truyền dữ liệu / khác | egress, SQS | 0.37 |
| **Tổng** | | **≈ 3.22** |

**Chi phí khác**

| Hạng mục | Chi tiết | Chi phí (USD/tháng) |
|---|---|---|
| Dịch vụ bên thứ ba | API OpenAQ + Open-Meteo (gói miễn phí) | 0.00 |
| **Tổng dự án** | | **≈ 3.22** (trần cứng: AWS Budget $8) |

## 7. Đánh giá rủi ro

| Rủi ro | Biện pháp giảm thiểu |
|---|---|
| **Vượt chi phí** | giới hạn quét Athena 10 GB mỗi truy vấn, serverless co về không, tiering/lifecycle S3, và một **AWS Budget ($8)** kèm billing alarm `>$8/month`. |
| **Dữ liệu lỗi thời / thiếu hụt nguồn** | `completeness_check` (`MissingStations` hàng giờ), tín hiệu chết âm thầm `DaysSinceLastNewMart`, một alarm `mart-stale`, và một cổng kiểm tra độ tươi dbt dựa trên truy vấn. |
| **Giới hạn tần suất API OpenAQ / lộ khóa** | khóa được giữ trong **Secrets Manager** (không bao giờ nằm trong state/env), backoff trên producer, và một **DLQ** trên luồng bất đồng bộ. |
| **Dự báo thiếu chính xác** | SARIMA theo từng trạm với **holdout-RMSE** phát lên CloudWatch + một alarm `ForecastRMSE`; dự báo được trình bày mang tính chỉ báo, không phải SLA. |
| **Tính sẵn sàng đơn vùng** | chấp nhận cho một bản demo; stack hoàn toàn tái lập được qua Terraform và có thể triển khai lại ở vùng khác. |

## 8. Kết quả kỳ vọng & Đội ngũ

### 8.1 Kết quả kỳ vọng

1. Pipeline đầu cuối trực tiếp: thu nạp → danh mục → mart → API → dashboard, trên dữ liệu hiện tại.
2. AQI EPA-2024 chính xác, được kiểm chứng bằng máy qua **unit test** của dbt.
3. Dự báo SARIMA 7 ngày trực tiếp kèm giám sát RMSE.
4. Hoàn toàn tái lập từ `terraform apply` (đã kiểm chứng từ một bản clone sạch).
5. Well-Architected: không còn rủi ro cao nào mở; nằm trong khung chi phí.

*Cả năm đều đã đạt và được kiểm chứng trực tiếp — xem [Workshop]({{% relref "/5-workshop" %}}) để biết bản
build tái lập được, và §2.8 của tài liệu kho mã để biết hồ sơ kỹ thuật.*

### 8.2 Giới hạn dự án

- **Phạm vi minh họa**, không phải dịch vụ công được cấp ngân sách: không có SLA cho người dùng thực, không
  có đối tượng tiêu dùng theo quy định; giới hạn trong danh sách 21 trạm OpenAQ (hiện 5 trạm đang hoạt động).
- **Các khí (NO₂/O₃/SO₂/CO)** được giữ ở dạng thô nhưng loại khỏi AQI (chúng cần ppm/ppb + cửa sổ dưới một
  ngày — một mục tiêu được ghi nhận là không nằm trong phạm vi ở mức độ chi tiết theo ngày).
- **QuickSight** bị vô hiệu hóa (chỉ dành cho Enterprise); BI được cung cấp bởi dashboard tĩnh nằm trong
  khung chi phí.

### 8.3 Đội ngũ thực hiện

| Tên | Vai trò | Liên hệ |
|---|---|---|
| thanhtrung102 | FCJ Cloud Intern — người thiết kế & xây dựng duy nhất (data engineering, IaC, ML, BI) | thanhtrungnsl2003@gmail.com |
| FCJ Program Mentors | Hướng dẫn & đánh giá (AWS Study Group · First Cloud Journey) | [cloudjourney.awsstudygroup.com](https://cloudjourney.awsstudygroup.com/) |

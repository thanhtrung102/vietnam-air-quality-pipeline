#!/usr/bin/env python3
"""
Vietnam Air Quality Pipeline — architecture diagrams (canonical source).

Lightweight, reproducible diagram-as-code: mingrammer `diagrams` (Python) +
Graphviz, rendering official AWS icons. Formatting adapts the FCJ convention
seen in the reference reports (numbered flow steps, nested AWS Cloud / Region
boxes, solid=data / dashed=control edges).

Produces TWO views (like the reference's cloud + development diagrams):
  docs/architecture.png            — AWS cloud/infrastructure view
  docs/architecture_lifecycle.png  — data lifecycle (dbt medallion) view

Render locally:
    pip install diagrams           # needs Graphviz `dot` on PATH
    python docs/architecture_diagram.py
CI (deploy-report.yml) runs this and copies both PNGs into report/static/images/.
"""
from diagrams import Diagram, Cluster, Edge
from diagrams.aws.analytics import Athena, GlueDataCatalog, KinesisDataStreams, KinesisDataFirehose
from diagrams.aws.compute import Lambda
from diagrams.aws.storage import S3
from diagrams.aws.integration import Eventbridge, SimpleNotificationServiceSns, SimpleQueueServiceSqs
from diagrams.aws.security import SecretsManager
from diagrams.aws.network import APIGateway
from diagrams.aws.devtools import Codebuild
from diagrams.aws.management import Cloudwatch, CloudwatchAlarm
from diagrams.aws.cost import Budgets
from diagrams.aws.general import User, InternetAlt1

graph_attr = {
    "fontsize": "22",
    "bgcolor": "white",
    "pad": "0.6",
    "splines": "ortho",
    "nodesep": "0.7",
    "ranksep": "1.2",
}

# numbered step marker (mimics the reference's ①②③ flow circles)
def step(n, **kw):
    return Edge(label=f"  {n}  ", fontsize="20", fontcolor="#2e4a62", **kw)

ORANGE = "#d97706"   # scheduler
RED = "#b91c1c"      # secrets / DLQ
GREEN = "#15803d"    # ingestion

# ─────────────────────────────────────────────────────────────────────────────
# View 1 — AWS cloud / infrastructure
# ─────────────────────────────────────────────────────────────────────────────
with Diagram("Vietnam Air Quality Pipeline — AWS Architecture",
             filename="docs/architecture", outformat="png", show=False,
             direction="LR", graph_attr=graph_attr):

    archive = S3("OpenAQ S3 Archive\n(us-east-1, 21 stations)")
    api_src = InternetAlt1("OpenAQ REST API v3")
    meteo = InternetAlt1("Open-Meteo ERA5")
    user = User("End user\n(browser)")

    with Cluster("AWS Cloud"):
        with Cluster("Region · ap-southeast-1 (no VPC)"):
            with Cluster("Schedule & Secrets"):
                eb = Eventbridge("EventBridge\n6 schedules")
                sm = SecretsManager("Secrets Manager\nopenaq/api_key")

            with Cluster("Ingestion (Lambda, arm64)"):
                l_batch = Lambda("batch_sync")
                l_stream = Lambda("streaming_producer")
                l_weather = Lambda("weather_ingest")

            with Cluster("Stream & Storage"):
                kds = KinesisDataStreams("Kinesis\nData Streams")
                fh = KinesisDataFirehose("Firehose")
                lake = S3("S3 data lake\nbatch·stream·weather")
                dlq = SimpleQueueServiceSqs("SQS DLQ")

            with Cluster("Catalog & Transform"):
                glue = GlueDataCatalog("Glue Catalog\npartition projection")
                athena = Athena("Athena\nopenaq_workgroup")
                dbt = Codebuild("CodeBuild · dbt\n17 models · 84 tests")

            with Cluster("Serving"):
                apigw = APIGateway("API Gateway\naqi_api · GeoJSON")
                forecast = Lambda("forecast_generate\nSARIMA 7-day")
                site = S3("S3 static site\ndashboard")

            with Cluster("Observability"):
                completeness = Lambda("completeness_check")
                cw = Cloudwatch("CloudWatch\n15 alarms")
                sns = SimpleNotificationServiceSns("SNS\nopenaq_alerts")

    with Cluster("us-east-1"):
        billing = CloudwatchAlarm("Billing alarm")
        budget = Budgets("AWS Budget $8")

    # numbered happy-path (solid), control/monitoring (dashed, unnumbered)
    archive >> step(1, color=GREEN) >> l_batch
    api_src >> step(1, color=GREEN) >> l_stream
    meteo >> step(1, color=GREEN) >> l_weather
    l_batch >> step(2) >> lake
    l_weather >> step(2) >> lake
    l_stream >> step(2) >> kds >> fh >> lake
    lake >> step(3) >> glue >> step(4) >> athena
    athena >> Edge(label="  5  ", fontsize="20", fontcolor="#2e4a62", style="dashed") >> dbt
    dbt >> Edge(label="openaq_mart") >> athena
    athena >> step(6) >> apigw
    athena >> step(6) >> forecast
    apigw >> step(7) >> site >> step(8) >> user

    # control / observability (dashed, no step number)
    eb >> Edge(color=ORANGE, style="dashed") >> [l_batch, l_stream, l_weather, dbt, forecast, completeness]
    sm >> Edge(color=RED, style="dashed") >> l_stream
    l_stream >> Edge(color=RED, style="dashed") >> dlq
    forecast >> Edge(style="dashed") >> cw
    completeness >> Edge(style="dashed") >> cw >> Edge(style="dashed") >> sns

# ─────────────────────────────────────────────────────────────────────────────
# View 2 — Data lifecycle (dbt medallion), analogous to the reference's dev view
# ─────────────────────────────────────────────────────────────────────────────
with Diagram("Vietnam Air Quality Pipeline — Data Lifecycle (dbt)",
             filename="docs/architecture_lifecycle", outformat="png", show=False,
             direction="LR", graph_attr={**graph_attr, "ranksep": "1.4"}):

    with Cluster("Raw zone — S3 raw/ (external tables)"):
        r_batch = S3("raw/batch/\nOpenAQ archive")
        r_stream = S3("raw/stream/\nOpenAQ API")
        r_weather = S3("raw/weather/\nERA5")

    cat = GlueDataCatalog("Glue Catalog\npartition projection")

    with Cluster("Staging (dbt views)"):
        stg_aq = Athena("stg_openaq_*\nclean · cast · cap 500")
        stg_wx = Athena("stg_weather")

    with Cluster("Intermediate (dbt)"):
        int_daily = Athena("int_station_daily\n+ EPA-2024 AQI")
        int_wx = Athena("int_weather_daily")

    with Cluster("Marts — dbt → Parquet (openaq_mart)"):
        m_aqi = S3("mart_daily_aqi")
        m_feat = S3("mart_lagged_features")
        m_fc = S3("mart_daily_forecast")
        m_health = S3("mart_health_* / compliance")

    with Cluster("Serving"):
        api = APIGateway("aqi_api\nGeoJSON · /analytics/*")
        fc = Lambda("forecast_generate\nSARIMA 7-day")
        dash = S3("S3 static dashboard")
        consumer = User("End user")

    r_batch >> step(1) >> cat
    r_stream >> step(1) >> cat
    r_weather >> step(1) >> cat
    cat >> step(2) >> stg_aq
    cat >> step(2) >> stg_wx
    stg_aq >> step(3) >> int_daily
    stg_wx >> step(3) >> int_wx
    int_daily >> step(4) >> [m_aqi, m_feat, m_health]
    int_wx >> step(4) >> m_feat
    m_feat >> Edge(label="  5  ", fontsize="20", fontcolor="#2e4a62") >> fc >> m_fc
    m_aqi >> step(6) >> api
    m_fc >> step(6) >> api
    m_health >> step(6) >> api
    api >> step(7) >> dash >> step(8) >> consumer

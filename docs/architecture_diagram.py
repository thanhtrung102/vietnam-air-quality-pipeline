#!/usr/bin/env python3
"""
Vietnam Air Quality Pipeline — AWS architecture diagram (canonical source).

Lightweight, reproducible diagram-as-code using mingrammer `diagrams`
(Python) + Graphviz. Renders official AWS service icons with automatic,
clean cluster layout — replacing the earlier awsdac source.

Render locally:
    pip install diagrams           # needs Graphviz `dot` on PATH
    python docs/architecture_diagram.py     # -> docs/architecture.png

CI (deploy-report.yml) runs this and copies the PNG into
report/static/images/architecture.png for the report site.
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
    "nodesep": "0.6",
    "ranksep": "1.1",
}

with Diagram(
    "Vietnam Air Quality Pipeline",
    filename="docs/architecture",
    outformat="png",
    show=False,
    direction="LR",
    graph_attr=graph_attr,
):
    archive = S3("OpenAQ S3 Archive\n(us-east-1, 21 stations)")
    api_src = InternetAlt1("OpenAQ REST API v3")
    meteo = InternetAlt1("Open-Meteo ERA5")
    user = User("End user\n(browser)")

    with Cluster("AWS Cloud  ·  ap-southeast-1 (no VPC)"):
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

    # Ingestion paths (green)
    archive >> Edge(color="darkgreen") >> l_batch >> lake
    api_src >> Edge(color="darkgreen") >> l_stream >> kds >> fh >> lake
    meteo >> Edge(color="darkgreen") >> l_weather >> lake
    l_stream >> Edge(color="firebrick", style="dashed") >> dlq
    sm >> Edge(color="firebrick", style="dashed") >> l_stream

    # Scheduler (orange dashed)
    eb >> Edge(color="darkorange", style="dashed") >> [l_batch, l_stream, l_weather, dbt, forecast, completeness]

    # Transform & serving
    lake >> glue >> athena
    athena >> Edge(style="dashed") >> dbt
    dbt >> Edge(label="openaq_mart") >> athena
    athena >> apigw
    athena >> forecast
    apigw >> site >> user

    # Observability
    forecast >> cw
    completeness >> cw >> sns

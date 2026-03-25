"""
Generate docs/architecture.png using the diagrams-as-code library.
Run from repo root: python docs/generate_diagram.py
"""
import os
from diagrams import Diagram, Cluster, Edge
from diagrams.aws.storage import S3
from diagrams.aws.analytics import Athena, Glue, KinesisDataStreams, KinesisDataFirehose
from diagrams.aws.management import Cloudwatch
from diagrams.aws.security import IAMRole
from diagrams.aws.general import General
from diagrams.aws.business import BusinessApplications
from diagrams.onprem.analytics import Dbt
from diagrams.onprem.workflow import Airflow  # used as Kestra stand-in
from diagrams.onprem.client import User
from diagrams.programming.language import Python
from diagrams.generic.blank import Blank

OUTPUT = os.path.join(os.path.dirname(__file__), "architecture")

graph_attr = {
    "fontsize": "13",
    "bgcolor": "white",
    "pad": "0.5",
    "splines": "ortho",
    "nodesep": "0.6",
    "ranksep": "1.0",
    "rankdir": "LR",
}

node_attr = {
    "fontsize": "11",
}

with Diagram(
    "Vietnam Air Quality Pipeline",
    filename=OUTPUT,
    outformat="png",
    show=False,
    graph_attr=graph_attr,
    node_attr=node_attr,
    direction="LR",
):

    # ── External sources ─────────────────────────────────────────────
    with Cluster("External Sources"):
        openaq_archive = S3("OpenAQ S3 Archive\n(us-east-1, public)")
        openaq_api     = General("OpenAQ API v3\n(REST / JSON)")

    # ── Orchestration ─────────────────────────────────────────────────
    with Cluster("Orchestration"):
        kestra = Airflow("Kestra\n(daily + 30-min flows)")

    # ── IaC ───────────────────────────────────────────────────────────
    with Cluster("Infrastructure as Code"):
        terraform = General("Terraform\n(manages all AWS resources)")

    # ── ap-southeast-1 ────────────────────────────────────────────────
    with Cluster("AWS ap-southeast-1"):

        with Cluster("Raw Zone — S3"):
            s3_batch  = S3("s3://openaq-pipeline-tt\n/raw/batch/\nlocationid={id}/year/month")
            s3_stream = S3("s3://openaq-pipeline-tt\n/raw/stream/\nyear/month/day/hour")

        with Cluster("Streaming"):
            kinesis_stream   = KinesisDataStreams("Kinesis\nData Stream\n(openaq_stream)")
            kinesis_firehose = KinesisDataFirehose("Kinesis\nFirehose")
            producer         = Python("Kinesis Producer\n(fetch_api.py)")

        with Cluster("Catalogue & Query"):
            glue    = Glue("Glue Data Catalog\n(openaq_raw DB)")
            athena  = Athena("Athena\n(openaq_workgroup)")

        with Cluster("Transform"):
            dbt_staging = Dbt("dbt Staging\nstg_measurements_*")
            dbt_int     = Dbt("dbt Intermediate\nint_measurements_enriched")
            dbt_mart    = Dbt("dbt Mart\nmart_daily_air_quality")

        with Cluster("Processed Zone — S3"):
            s3_processed = S3("s3://openaq-pipeline-tt\n/processed/\nmart_daily_air_quality/\n(Iceberg, partitioned by date)")

        with Cluster("Visualisation"):
            quicksight = BusinessApplications("QuickSight\nSPICE datasets\n+ Dashboard")

        with Cluster("Monitoring"):
            cloudwatch = Cloudwatch("CloudWatch\n(Kinesis metrics\n+ S3 events)")

        iam = IAMRole("IAM Roles\n(kestra / glue /\ndbt / quicksight)")

    # ── End consumer ──────────────────────────────────────────────────
    analyst = User("Analyst / Dashboard\nConsumer")

    # ── Edges: Batch path ─────────────────────────────────────────────
    openaq_archive >> Edge(label="aws s3 sync\n(cross-region egress)") >> s3_batch
    kestra >> Edge(label="triggers\ndaily sync", style="dashed") >> openaq_archive

    # ── Edges: Streaming path ─────────────────────────────────────────
    openaq_api >> Edge(label="HTTP GET\n/measurements") >> producer
    producer   >> Edge(label="PutRecords") >> kinesis_stream
    kinesis_stream   >> kinesis_firehose
    kinesis_firehose >> Edge(label="S3 delivery\n(Parquet)") >> s3_stream
    kestra >> Edge(label="triggers\n30-min poll", style="dashed") >> producer

    # ── Edges: Catalogue ─────────────────────────────────────────────
    s3_batch  >> Edge(label="Glue Crawler") >> glue
    s3_stream >> Edge(label="Glue Crawler") >> glue
    glue      >> athena

    # ── Edges: Transform ─────────────────────────────────────────────
    athena     >> dbt_staging
    dbt_staging >> dbt_int
    dbt_int     >> dbt_mart
    dbt_mart    >> Edge(label="CTAS / INSERT\n(Iceberg)") >> s3_processed
    kestra      >> Edge(label="dbt run", style="dashed") >> dbt_staging

    # ── Edges: Visualisation ─────────────────────────────────────────
    s3_processed >> Edge(label="Athena query\nSPICE refresh") >> quicksight
    quicksight   >> analyst

    # ── Edges: Monitoring ────────────────────────────────────────────
    kinesis_stream >> Edge(style="dotted") >> cloudwatch
    s3_batch       >> Edge(style="dotted") >> cloudwatch

    # ── Edges: IaC ───────────────────────────────────────────────────
    terraform >> Edge(label="provisions", style="dashed", color="gray") >> iam

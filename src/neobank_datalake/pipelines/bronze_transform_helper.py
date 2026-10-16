"""Bronze transforms. No dlt/SDK imports or side effects, so it's unit-testable
without a Databricks runtime. Pipeline wiring is in src/pipelines/bronze.py.
"""
from __future__ import annotations

from pyspark.sql import DataFrame, SparkSession
from pyspark.sql import functions as F


def add_ingestion_metadata(df: DataFrame) -> DataFrame:
    """Add _ingested_at (processing time) and _source_file (from _metadata.file_path)."""
    return (
        df.withColumn("_ingested_at", F.current_timestamp())
          .withColumn("_source_file", F.col("_metadata.file_path"))
    )


def configure_reader(spark: SparkSession, fmt: str, **opts):
    """Auto Loader reader with options set, not loaded. spark is passed in so tests can mock it."""
    reader = (
        spark.readStream.format("cloudFiles")
        .option("cloudFiles.format", fmt)
        .option("cloudFiles.inferColumnTypes", "true")
        .option("cloudFiles.schemaEvolutionMode", "addNewColumns")
    )
    for key, value in opts.items():
        reader = reader.option(key, value)
    return reader


def build_autoloader(spark: SparkSession, path: str, fmt: str, **opts) -> DataFrame:
    """Load path with Auto Loader. Audit columns are added separately (add_ingestion_metadata)."""
    return configure_reader(spark, fmt, **opts).load(path)
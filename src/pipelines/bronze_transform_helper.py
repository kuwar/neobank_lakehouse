"""Pure transformation logic for the bronze layer.

This module deliberately has ZERO Databricks-runtime dependencies:
no `dlt`, no `databricks.sdk`, and no module-level side effects.

That is what makes it importable — and therefore unit-testable — on a
laptop or in CI, where the Databricks runtime does not exist. The thin
Databricks wiring lives in `bronze_pipeline.py` instead.
"""
from __future__ import annotations

from pyspark.sql import DataFrame, SparkSession
from pyspark.sql import functions as F


def add_ingestion_metadata(df: DataFrame) -> DataFrame:
    """Attach audit columns to a raw ingested batch.

    - `_ingested_at`: wall-clock time the batch was processed.
    - `_source_file`: the file each row was read from, pulled from Spark's
      hidden `_metadata` file-metadata column.

    This is a pure transform (input DataFrame -> output DataFrame) with no
    I/O and no runtime globals, so it is the primary unit-testable seam.
    """
    return (
        df.withColumn("_ingested_at", F.current_timestamp())
          .withColumn("_source_file", F.col("_metadata.file_path"))
    )


def configure_reader(spark: SparkSession, fmt: str, **opts):
    """Build a configured Auto Loader (cloudFiles) stream reader.

    Pure wiring: no `.load()`, no Spark SQL functions — just option setup.
    `spark` is injected as a parameter (not a module global) so tests can pass
    a mock and assert on the configured options without touching storage or
    needing a live SparkContext.
    """
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
    """Configure the reader and load the path. Enrichment is applied separately
    by the pipeline (via `add_ingestion_metadata`) so each function does one job.
    """
    return configure_reader(spark, fmt, **opts).load(path)
"""Integration tests: exercise ingestion against REAL files on disk.

Marked `@pytest.mark.integration` so CI can run the fast unit tests alone with
`pytest -m "not integration"` and run these (slower, touch the filesystem and
the streaming engine) in a separate job.

Two levels of fidelity:

1. Batch read  — the simplest check that `_metadata.file_path` resolves against
   real file reads and flows through `add_ingestion_metadata`.

2. Streaming read — the important one. The real bronze pipeline is a STREAM
   (Auto Loader). Auto Loader's `format("cloudFiles")` is Databricks-only, but
   open-source Structured Streaming's file source is a faithful local stand-in:
   same readStream API, same micro-batch execution, same `_metadata` column.
   `trigger(availableNow=True)` drains all currently-available files and stops,
   which makes a stream testable like a batch. This exercises the streaming code
   path that the batch test can't.
"""
from pathlib import Path

import pytest
from pyspark.sql import DataFrame, SparkSession
from pyspark.sql import functions as F

from neobank_datalake.pipelines.bronze_transform_helper import add_ingestion_metadata

pytestmark = pytest.mark.integration

FIXTURES = Path(__file__).resolve().parent / "fixtures"

# Streaming file sources require an explicit schema (no inference by default),
# so we declare the transactions shape once here.
TXN_SCHEMA = "txn_id string, user_id string, amount string, currency string, ts string"


def _stream_to_memory(spark: SparkSession, path: str, checkpoint: str, name: str) -> DataFrame:
    """Read `path` as a stream, enrich it, drain it once, and return the result.

    Uses the in-memory sink + availableNow trigger so the streaming query runs to
    completion and its output can be queried as a normal table in assertions.
    """
    stream = (
        spark.readStream.format("csv")
        .schema(TXN_SCHEMA)
        .option("header", "true")
        .load(path)
    )
    enriched = add_ingestion_metadata(stream)
    query = (
        enriched.writeStream.format("memory")
        .queryName(name)
        .option("checkpointLocation", checkpoint)
        .trigger(availableNow=True)
        .start()
    )
    query.awaitTermination()
    return spark.table(name)


def test_batch_read_enriches_real_files(spark):
    """Simplest fidelity: enrichment works against real files read in batch."""
    df = spark.read.option("header", "true").csv(str(FIXTURES))
    out = add_ingestion_metadata(df)

    assert out.count() == 5                                           # two files
    assert out.filter(F.col("_source_file").isNull()).count() == 0   # every row tagged
    files = {r._source_file.split("/")[-1] for r in out.select("_source_file").collect()}
    assert files == {"batch_001.csv", "batch_002.csv"}


def test_streaming_ingest_mirrors_autoloader(spark, tmp_path):
    """Faithful check: the STREAMING path (what production actually runs) reads
    every source file exactly once and enriches each row correctly."""
    checkpoint = str(tmp_path / "ckpt")
    out = _stream_to_memory(spark, str(FIXTURES), checkpoint, "bronze_txn_stream")

    # all 5 rows across both files were ingested by the stream
    assert out.count() == 5

    # audit columns are populated for every streamed row
    assert out.filter(F.col("_source_file").isNull()).count() == 0
    assert dict(out.dtypes)["_ingested_at"] == "timestamp"

    # provenance: each source file is tracked, with the right row counts
    assert out.filter(F.col("_source_file").contains("batch_001.csv")).count() == 3
    assert out.filter(F.col("_source_file").contains("batch_002.csv")).count() == 2
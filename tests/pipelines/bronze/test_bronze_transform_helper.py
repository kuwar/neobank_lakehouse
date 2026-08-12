"""Unit tests for the pure transform logic in `transforms.py`.

These run fully locally against a small in-memory DataFrame — no cluster,
no cloud storage, no Databricks runtime.
"""
from pyspark.sql import Row, functions as F

from pipelines.bronze_transform_helper import add_ingestion_metadata


def test_adds_audit_columns(raw_batch):
    """The two audit columns are added and _source_file comes from _metadata."""
    out = add_ingestion_metadata(raw_batch)

    # 1. the audit columns exist
    assert "_ingested_at" in out.columns
    assert "_source_file" in out.columns

    # 2. _source_file is pulled from _metadata.file_path, in order
    files = [r._source_file for r in out.orderBy("user_id").collect()]
    assert files == ["/vol/tx/f1.csv", "/vol/tx/f2.csv"]


def test_ingested_at_is_non_null_timestamp(raw_batch):
    """current_timestamp() is non-deterministic — assert type & non-null,
    never an exact clock value (that would be a flaky test)."""
    out = add_ingestion_metadata(raw_batch)

    ts_type = dict(out.dtypes)["_ingested_at"]
    assert ts_type == "timestamp"
    assert out.filter(F.col("_ingested_at").isNull()).count() == 0


def test_preserves_original_columns_and_rowcount(raw_batch):
    """Enrichment must not drop, duplicate, or mangle the source rows."""
    out = add_ingestion_metadata(raw_batch)

    # original columns survive
    assert "user_id" in out.columns
    assert "amount" in out.columns

    # no rows added or lost
    assert out.count() == 2

    # original values untouched
    rows = {r.user_id: r.amount for r in out.collect()}
    assert rows == {"a": 10, "b": 20}


def test_handles_empty_input(spark):
    """An empty batch enriches to an empty result with the new schema —
    a common edge case on the first (empty) micro-batch of a stream."""
    schema = "user_id string, amount int, _metadata struct<file_path:string>"
    empty = spark.createDataFrame([], schema)

    out = add_ingestion_metadata(empty)

    assert out.count() == 0
    assert "_ingested_at" in out.columns
    assert "_source_file" in out.columns
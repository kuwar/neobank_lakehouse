"""Shared fixtures, auto-discovered by pytest for every test in this tree.

The `spark` fixture is a serverless session via Databricks Connect (through the
project's one acquisition helper), so tests exercise the real engine and Unity
Catalog semantics — driven from your laptop / CI.
"""
import pytest
from pyspark.sql import Row


@pytest.fixture(scope="session")
def spark():
    """Serverless Spark via Databricks Connect, built once for the whole run.

    Reuses `get_spark()` so tests and production acquire the session identically.
    We do NOT call .stop() — the serverless session is managed remotely and is
    shared; stopping it is unnecessary and can disrupt a reused connection.
    """
    from neobank_datalake.db_context import get_spark

    return get_spark()


@pytest.fixture
def raw_batch(spark):
    """A small DataFrame mimicking Auto Loader's output: real columns plus a
    `_metadata` struct carrying `file_path`. Function-scoped for a clean copy."""
    return spark.createDataFrame([
        Row(user_id="a", amount=10, _metadata=Row(file_path="/vol/tx/f1.csv")),
        Row(user_id="b", amount=20, _metadata=Row(file_path="/vol/tx/f2.csv")),
    ])
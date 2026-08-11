"""Shared fixtures, auto-discovered by pytest for every test in this tree.

pytest loads this file automatically (no import needed). Any fixture defined
here is available to every test module in `tests/` and its subdirectories,
resolved by matching the fixture name to a test's parameter name.
"""
import pytest
from pyspark.sql import Row, SparkSession


@pytest.fixture(scope="session")
def spark():
    """A local Spark session, built once for the whole test run.

    scope="session" is the key choice: a fresh JVM per test would make the
    suite crawl. The teardown after `yield` runs even if a test fails.
    """
    session = (
        SparkSession.builder
        .master("local[2]")
        .appName("neobank-lakehouse-unit-tests")
        .config("spark.sql.shuffle.partitions", "1")   # tiny data -> 1 partition
        .config("spark.ui.enabled", "false")           # no web UI in tests
        .getOrCreate()
    )
    yield session
    session.stop()


@pytest.fixture
def raw_batch(spark):
    """A small DataFrame that mimics what Auto Loader hands to our transform:
    real columns plus a `_metadata` struct carrying `file_path`.

    Function-scoped (the default) so every test gets a clean copy. It depends
    on the `spark` fixture, which pytest resolves automatically.
    """
    return spark.createDataFrame([
        Row(user_id="a", amount=10, _metadata=Row(file_path="/vol/tx/f1.csv")),
        Row(user_id="b", amount=20, _metadata=Row(file_path="/vol/tx/f2.csv")),
    ])
"""Runtime handles (spark, dbutils, pipeline decorators) for Databricks and local dev.

Only this module touches the environment; everything else takes these as arguments.
Open-source pyspark is never used: it conflicts with databricks-connect.
"""
from __future__ import annotations

from types import ModuleType
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    # Type hints only; the wheel has no pyspark dependency.
    from databricks.sdk.dbutils import RemoteDbUtils
    from pyspark.sql import SparkSession


def get_spark() -> SparkSession:
    """Active session on Databricks; serverless Databricks Connect session locally."""
    # pyspark comes from the runtime on Databricks and from databricks-connect locally.
    from pyspark.sql import SparkSession

    active = SparkSession.getActiveSession()
    if active is not None:
        return active

    from databricks.connect import DatabricksSession

    return DatabricksSession.builder.serverless(True).getOrCreate()


def get_dbutils(spark: SparkSession) -> RemoteDbUtils | None:
    """dbutils from the SDK runtime or the Connect session; None if unavailable."""
    try:
        from databricks.sdk.runtime import dbutils

        return dbutils
    except ImportError:
        pass

    try:
        return spark.session.dbutils  # type: ignore[attr-defined]
    except Exception:
        return None
    



def get_dlt() -> ModuleType:
    """Pipeline decorator module: pyspark.pipelines, falling back to the legacy dlt stub.

    Usage at the top of a pipeline file:

        dp = get_dlt()

        @dp.table
        def my_table(): ...

    Decorators only do anything when the file runs inside a pipeline.
    """
    try:
        from pyspark import pipelines as dp
    except ImportError:
        import dlt as dp
    return dp
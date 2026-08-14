"""Single place that knows how to acquire runtime handles (spark, dbutils).

Everything else in the project receives these as parameters — this is the only
module that reaches for the environment, so portability logic lives in one spot
and the rest of the code stays testable and lint-clean.
"""
from __future__ import annotations

from pyspark.sql import SparkSession


def get_spark() -> SparkSession:
    """Return the active Spark session, portably.

    - SDP/Lakeflow pipeline or Databricks notebook: the runtime already created
      a session, so getActiveSession() returns it.
    - Standalone script / pure-local run: none is active, so build one.
    """
    return SparkSession.getActiveSession() or SparkSession.builder.getOrCreate()


def get_dbutils(spark: SparkSession):
    """Return dbutils, portably. Returns None when unavailable (e.g. pure
    open-source local run), so callers can decide what to do.

    - Databricks runtime (and SDK-backed local, if env is configured):
      databricks.sdk.runtime.
    - databricks-connect local dev: pyspark.dbutils.DBUtils(spark).
    """
    try:
        from databricks.sdk.runtime import dbutils
        return dbutils
    except ImportError:
        pass
    
    try:
        from pyspark.dbutils import DBUtils
        return DBUtils(spark)
    except ImportError:
        return None
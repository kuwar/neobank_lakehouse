"""Single place that knows how to acquire runtime handles (spark, dbutils).

Everything else in the project receives these as parameters — this is the only
module that reaches for the environment, so portability logic lives in one spot
and the rest of the code stays testable and lint-clean.

Session acquisition order:
  1. On Databricks (job / notebook / Lakeflow pipeline): the runtime already
     created a session — reuse it via getActiveSession().
  2. Local dev: create a serverless session through Databricks Connect.
We never install or fall back to open-source pyspark, which would conflict with
the databricks-connect namespace.
"""
from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    # Import only for type checkers / IDEs. Not needed (or installed) at runtime,
    # so the wheel carries no pyspark dependency.
    from pyspark.sql import SparkSession
    from databricks.sdk.dbutils import RemoteDbUtils


def get_spark() -> SparkSession:
    """Return the active Spark session, portably.

    - Databricks runtime (job, notebook, Lakeflow/SDP pipeline): the runtime
      already created a session, so getActiveSession() returns it.
    - Local dev: none is active, so build a serverless session via Databricks
      Connect.
    """
    # On Databricks the pyspark namespace is provided by the runtime; locally it
    # is provided by databricks-connect. Either way this import resolves without
    # pyspark being a declared dependency.
    from pyspark.sql import SparkSession

    active = SparkSession.getActiveSession()
    if active is not None:
        return active

    # Not on Databricks -> connect to serverless compute.
    from databricks.connect import DatabricksSession

    return DatabricksSession.builder.serverless(True).getOrCreate()


def get_dbutils(spark: SparkSession) -> RemoteDbUtils | None:
    """Return dbutils, portably. Returns None when unavailable, so callers can
    decide what to do.

    - Databricks runtime (and SDK-backed local, if the env is configured):
      databricks.sdk.runtime.dbutils.
    - databricks-connect local dev: DBUtils bound to the Connect session.
    """
    try:
        from databricks.sdk.runtime import dbutils

        return dbutils
    except ImportError:
        pass

    try:
        # databricks-connect exposes DBUtils via the WorkspaceClient bound to
        # the active Connect session.
        return spark.session.dbutils  # type: ignore[attr-defined]
    except Exception:
        return None
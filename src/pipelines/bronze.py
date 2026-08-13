# Databricks notebook source
# ─────────────────────────────────────────────────────────────────────────────
# BRONZE — raw, append-only ingest, on Apache Spark Declarative Pipelines (SDP).
#
# Multi-schema publishing: this file emits tables into the BRONZE schema by
# giving each @dp.table a FULLY-QUALIFIED name (catalog.schema.table). This lets
# one pipeline span bronze/silver/gold — a silver file would qualify into the
# silver schema the same way — instead of every dataset landing in the single
# default schema set in the pipeline config.
#
# Requires the pipeline to be in DEFAULT publishing mode (the default for new
# pipelines) and Unity Catalog. You need USE CATALOG on the target catalog and
# create privileges on the target schema; the schema is created on write if absent.
# ─────────────────────────────────────────────────────────────────────────────
from pyspark import pipelines as dp
from pyspark.sql import SparkSession

from pipelines.bronze_transform_helper import add_ingestion_metadata, build_autoloader

spark = SparkSession.getActiveSession()


def configure(spark):
    """Read pipeline config. Returns (catalog, bronze_schema, source_root)."""
    catalog = spark.conf.get("neobank.catalog")
    bronze = spark.conf.get("neobank.bronze_schema")
    volume = spark.conf.get("neobank.volume")
    root = f"/Volumes/{catalog}/bronze/{volume}"
    return catalog, bronze, root


catalog, bronze, root = configure(spark)


def _qualify(table: str) -> str:
    """Build a fully-qualified catalog.schema.table name from pipeline config,
    so the target schema stays config-driven rather than hard-coded."""
    return f"{catalog}.{bronze}.{table}"


def _ingest(path, fmt, **opts):
    """Load a source with Auto Loader and attach audit columns.

    NOTE: format("cloudFiles") is Auto Loader — Databricks-only. For local
    open-source SDP, swap for spark.readStream.format(fmt).load(path).
    """
    return add_ingestion_metadata(build_autoloader(spark, path, fmt, **opts))


@dp.table(name=_qualify("bronze_transactions"),
          comment="Raw transactions as delivered by the source.")
def bronze_transactions():
    return _ingest(f"{root}/transactions", "csv", header="true")


@dp.table(name=_qualify("bronze_users"),
          comment="Raw users/customers.")
def bronze_users():
    return _ingest(f"{root}/users", "csv", header="true")


@dp.table(name=_qualify("bronze_cards"),
          comment="Raw payment cards.")
def bronze_cards():
    return _ingest(f"{root}/cards", "csv", header="true")


@dp.table(name=_qualify("bronze_device_events"),
          comment="Raw device login/session events.")
def bronze_device_events():
    return _ingest(f"{root}/device_events", "json")


@dp.table(name=_qualify("bronze_notifications"),
          comment="Raw notification delivery events.")
def bronze_notifications():
    return _ingest(f"{root}/notifications", "json")
# Databricks notebook source
# Bronze: raw, append-only ingest with Auto Loader.
# Table names are fully qualified so one pipeline can publish to bronze/silver/gold
# (requires the default publishing mode).
from neobank_datalake.db_context import get_dlt, get_spark
from neobank_datalake.pipelines.bronze_transform_helper import add_ingestion_metadata, build_autoloader

dp = get_dlt()
spark = get_spark()


def configure(spark):
    """Read pipeline config. Returns (catalog, bronze_schema, source_root)."""
    catalog = spark.conf.get("neobank.catalog")
    bronze = spark.conf.get("neobank.bronze_schema")
    volume = spark.conf.get("neobank.volume")
    root = f"/Volumes/{catalog}/bronze/{volume}"
    return catalog, bronze, root


catalog, bronze, root = configure(spark)


def _qualify(table: str) -> str:
    """catalog.bronze_schema.table, from pipeline config."""
    return f"{catalog}.{bronze}.{table}"


def _ingest(path, fmt, **opts):
    """Auto Loader read plus audit columns. cloudFiles is Databricks-only."""
    return add_ingestion_metadata(build_autoloader(spark, path, fmt, **opts))


@dp.table(name=_qualify("bronze_transactions"),
          comment="Raw transactions as delivered by the source.")
def bronze_transactions():
    return _ingest(f"{root}/transactions", "csv", header="true")


# TODO - user must be treated as SCD Type - 2
@dp.table(name=_qualify("bronze_users"),
          comment="Raw users/customers.")
def bronze_users():
    return _ingest(f"{root}/users", "csv", header="true")


@dp.table(name=_qualify("bronze_cards"),
          comment="Raw payment cards.")
def bronze_cards():
    return _ingest(f"{root}/cards", "csv", header="true")

# MCC codes
@dp.materialized_view(
    name=_qualify("bronze_mcc_codes"),
    comment="Raw mcc lookup table"
)
def bronze_mcc_codes():    
    return add_ingestion_metadata(
        spark.read.text(
            f"{root}/mcc",
            wholetext=True,          # read entire file as a single string (handles multi-line)
        )
    )

@dp.table(name=_qualify("bronze_device_events"),
          comment="Raw device login/session events.")
def bronze_device_events():
    return _ingest(f"{root}/device_events", "json")


@dp.table(name=_qualify("bronze_notifications"),
          comment="Raw notification delivery events.")
def bronze_notifications():
    return _ingest(f"{root}/notifications", "json")
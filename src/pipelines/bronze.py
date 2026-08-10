# Databricks notebook source
# ─────────────────────────────────────────────────────────────────────────────
# BRONZE — raw, append-only ingest from the volume using Auto Loader (cloudFiles).
# Auto Loader scales to millions of files and only processes new data each run,
# which is what makes this pipeline incremental and cost-efficient.
# ─────────────────────────────────────────────────────────────────────────────
import dlt
from databricks.sdk.runtime import spark
from pyspark.sql import functions as F

catalog = spark.conf.get("neobank.catalog")
bronze  = spark.conf.get("neobank.bronze_schema")
volume = spark.conf.get("neobank.volume")
root = f"/Volumes/{catalog}/bronze/{volume}"


spark.sql(f"USE CATALOG {catalog}")
spark.sql(f"USE SCHEMA {bronze}") 

def _autoload(path, fmt, **opts):
    reader = (spark.readStream.format("cloudFiles")
              .option("cloudFiles.format", fmt)
              .option("cloudFiles.inferColumnTypes", "true")
              .option("cloudFiles.schemaEvolutionMode", "addNewColumns"))
    for k, v in opts.items():
        reader = reader.option(k, v)
    return (reader.load(path)
            .withColumn("_ingested_at", F.current_timestamp())
            .withColumn("_source_file", F.col("_metadata.file_path")))


@dlt.table(comment="Raw transactions as delivered by the source.")
def bronze_transactions():
    return _autoload(f"{root}/transactions", "csv", header="true")


@dlt.table(comment="Raw users/customers.")
def bronze_users():
    return _autoload(f"{root}/users", "csv", header="true")


@dlt.table(comment="Raw payment cards.")
def bronze_cards():
    return _autoload(f"{root}/cards", "csv", header="true")


@dlt.table(comment="Raw device login/session events.")
def bronze_device_events():
    return _autoload(f"{root}/device_events", "json")


@dlt.table(comment="Raw notification delivery events.")
def bronze_notifications():
    return _autoload(f"{root}/notifications", "json")
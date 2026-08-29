# Databricks notebook source
# ─────────────────────────────────────────────────────────────────────────────
# GOLD — a query-able star schema. Conformed dimensions + additive fact tables
# are exactly what BI tools and metric views expect: fast joins, clear grain.
#
#   dim_users ─┐                 ┌─ dim_date
#              ├─ fact_transactions
#   dim_cards ─┘                 └─ dim_merchant
#                                └─ dim_mcc_codes
#   dim_users ─── fact_notifications
#   dim_users ─── fact_device_activity
# ─────────────────────────────────────────────────────────────────────────────
from pyspark.sql import functions as F

from neobank_datalake.db_context import get_dlt, get_spark

dp = get_dlt()
spark = get_spark()

catalog = spark.conf.get("neobank.catalog")
bronze  = spark.conf.get("neobank.bronze_schema")
silver  = spark.conf.get("neobank.silver_schema")
gold  = spark.conf.get("neobank.gold_schema")
spark.sql(f"USE CATALOG {catalog}")
spark.sql(f"USE SCHEMA {gold}") 

# ── Dimensions ───────────────────────────────────────────────────────────────
@dp.table(comment="Customer dimension.")
def dim_users():
    return (
        dp.read(f"{catalog}.{silver}.silver_users")
        .withColumn("income_band",
            F.when(F.col("yearly_income") < 30000, "low")
             .when(F.col("yearly_income") < 80000, "mid")
             .otherwise("high"))
        .withColumn("credit_band",
            F.when(F.col("credit_score") < 580, "poor")
             .when(F.col("credit_score") < 670, "fair")
             .when(F.col("credit_score") < 740, "good")
             .otherwise("excellent"))
    )


@dp.table(comment="Card dimension.")
def dim_cards():
    return dp.read(f"{catalog}.{silver}.silver_cards")


@dp.materialized_view(comment="Merchant-category dimension.")
def dim_merchant():
    # Distinct merchants observed in transactions.
    return (
        dp.read(f"{catalog}.{silver}.silver_transactions")
        .select("merchant_id", "merchant_city", "merchant_state")
        # A merchant can appear under several city (large retailers, franchises, aggregators)
        .dropDuplicates(["merchant_id", "merchant_city"])
    )

@dp.materialized_view(comment="MCC codes dimensions")
def dim_mcc_code():
    return spark.read.table(f"{catalog}.{silver}.silver_mcc_codes")


@dp.table(comment="Date dimension for time-series analysis.")
def dim_date():
    dates = (
        dp.read(f"{catalog}.{silver}.silver_transactions")
        .select(F.col("transaction_date").alias("date"))
        .union(dp.read(f"{catalog}.{silver}.silver_notifications").select(F.col("sent_date").alias("date")))
        .where("date IS NOT NULL").distinct()
    )
    return (dates
        .withColumn("year", F.year("date"))
        .withColumn("month", F.month("date"))
        .withColumn("day_of_week", F.dayofweek("date"))
        .withColumn("is_weekend", F.dayofweek("date").isin(1, 7)))


# ── Facts ────────────────────────────────────────────────────────────────────
@dp.table(
    comment="Transaction fact at grain = one row per transaction.",
    table_properties={"delta.autoOptimize.optimizeWrite": "true"},
)
def fact_transactions():
    return (
        dp.read(f"{catalog}.{silver}.silver_transactions")
        .select(
            "transaction_id", "client_id", "card_id", "merchant_id", "mcc",
            "transaction_ts", "transaction_date",
            "amount", "use_chip", "is_declined", 
        )
        .withColumn("is_fraud", F.lit(False))   # join train_fraud_labels here in a real build
    )


@dp.table(comment="Notification fact at grain = one row per notification.")
def fact_notifications():
    return (
        dp.read(f"{catalog}.{silver}.silver_notifications")
        .select(
            "notification_id", "client_id", "channel", "category",
            "sent_ts", "sent_date", "opened"
        )
    )


@dp.table(comment="Device activity fact at grain = one row per session/event.")
def fact_device_activity():
    return (
        dp.read(f"{catalog}.{silver}.silver_device_events")
        .select("client_id", "device_id", "os", "event_type", "event_ts", "event_date")
    )
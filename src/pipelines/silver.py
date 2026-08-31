# Databricks notebook source
# ─────────────────────────────────────────────────────────────────────────────
# SILVER — clean, type, conform, and enforce data quality.
# @dp.expect_* rules make quality a first-class, monitored part of the pipeline:
# bad rows are dropped (and counted) instead of silently poisoning analytics.
# ─────────────────────────────────────────────────────────────────────────────
from pyspark.sql import functions as F
from pyspark.sql import types as T

from neobank_datalake.db_context import get_dlt, get_spark

dp = get_dlt()
spark = get_spark()

catalog = spark.conf.get("neobank.catalog")
bronze  = spark.conf.get("neobank.bronze_schema")
silver  = spark.conf.get("neobank.silver_schema")
spark.sql(f"USE CATALOG {catalog}")
spark.sql(f"USE SCHEMA {silver}") 


# ── Users ────────────────────────────────────────────────────────────────────
@dp.table(comment="Cleaned customers, one row per client.")
@dp.expect_or_drop("valid_client", "client_id IS NOT NULL")
@dp.expect("plausible_age", "current_age BETWEEN 16 AND 110")
def silver_users():
    return (
        dp.read(f"{catalog}.{bronze}.bronze_users")
        .select(
            F.col("id").cast("int").alias("client_id"),
            F.col("current_age").cast("int").alias("current_age"),
            F.col("retirement_age").cast("int").alias("retirement_age"),
            F.col("birth_year").cast("int").alias("birth_year"),
            F.col("birth_month").cast("int").alias("birth_month"),
            F.col("gender"),
            F.col("address"),
            F.col("latitude"),
            F.col("longitude"),
            F.regexp_replace("per_capita_income", r"[$,]", "").cast("double").alias("per_capita_income"),
            F.regexp_replace("yearly_income", r"[$,]", "").cast("double").alias("yearly_income"),
            F.regexp_replace("total_debt", r"[$,]", "").cast("double").alias("total_debt"),
            F.col("credit_score").cast("int").alias("credit_score"),
            F.col("num_credit_cards").cast("int").alias("num_credit_cards"),
        )
        .dropDuplicates(["client_id"])
    )


# ── Cards ────────────────────────────────────────────────────────────────────
@dp.table(comment="Cleaned cards.")
@dp.expect_or_drop("valid_card", "card_id IS NOT NULL AND client_id IS NOT NULL")
def silver_cards():
    return (
        dp.read(f"{catalog}.{bronze}.bronze_cards")
        .select(
            F.col("id").cast("int").alias("card_id"),
            F.col("client_id").cast("int").alias("client_id"),
            F.col("card_brand"),
            F.col("card_type"),
            F.col("card_number"),
            F.col("expires"),
            # cvv has no analytical use whatsoever. Drop it
            # F.col("cvv"),
            F.col("has_chip"),
            F.col("num_cards_issued"),
            F.regexp_replace("credit_limit", r"[$,]", "").cast("double").alias("credit_limit"),
            F.col("acct_open_date"),
            F.col("year_pin_last_changed"),
            F.col("card_on_dark_web"),
        )
        # open date -> first of the month
        .withColumn("acct_open_date", F.to_date(F.col("acct_open_date"), "MM/yyyy"))
        # expiry -> parse to first of month, then push to the LAST day (valid-through)
        .withColumn("expires", F.last_day(F.to_date(F.col("expires"), "MM/yyyy")))
        .dropDuplicates(["card_id"])
    )


# ── Transactions ─────────────────────────────────────────────────────────────
@dp.table(comment="Cleaned transactions with parsed amount and MCC join.")
@dp.expect_or_drop("valid_txn", "transaction_id IS NOT NULL AND client_id IS NOT NULL")
@dp.expect("nonzero_amount", "amount <> 0")
def silver_transactions():
    tx = (
        dp.read(f"{catalog}.{bronze}.bronze_transactions")
        .select(
            F.col("id").cast("long").alias("transaction_id"),
            F.to_timestamp("date").alias("transaction_ts"),
            F.col("client_id").cast("int").alias("client_id"),
            F.col("card_id").cast("int").alias("card_id"),
            # Amounts arrive like "$-77.00" — strip symbols and cast.
            F.regexp_replace("amount", r"[$,]", "").cast("double").alias("amount"),
            F.col("use_chip"),
            F.col("merchant_id").cast("int").alias("merchant_id"),
            F.col("merchant_city"),
            F.col("merchant_state"),
            F.col("zip"),
            F.col("mcc").cast("int").alias("mcc"),
            F.coalesce(F.col("errors"), F.lit("")).alias("errors"),
        )
        .withColumn("is_declined", F.col("errors") != "")
        # All the online transaction has merchant state as null
        # so fill it with 'ONLINE' in original transactions
        .withColumn(
            "merchant_state", 
            F.when(F.col("merchant_state").isNull(), F.lit("ONLINE")).otherwise(F.col("merchant_state"))
        )
        # set zip to 'ONLINE' if the merchant_city is 'ONLINE' 
        # and set zip to '' if zip is null
        .withColumn(
            "zip",
            F.when(F.col("merchant_city") == "ONLINE", F.lit("ONLINE"))
            .when(F.col("zip").isNull(), F.lit(""))
            .otherwise(F.col("zip").cast("long").cast("string"))
        )
    )
    return tx.withColumn("transaction_date", F.to_date("transaction_ts"))


# ── MCC codes ────────────────────────────────────────────────────────────
@dp.materialized_view(
    name="silver_mcc_codes",
    comment="Merchant Category Codes: one row per code.",
)
@dp.expect_all_or_drop({"mcc_code_valid": "mcc RLIKE '^[0-9]{4}$'"})
def silver_mcc_codes():
    return (
        dp.read(f"{catalog}.{bronze}.bronze_mcc_codes")
        .select(F.from_json("value", T.MapType(T.StringType(), T.StringType())).alias("m"))
        .select(F.explode("m").alias("mcc", "mcc_description"))
        .withColumn("mcc", F.col("mcc").cast("integer"))
    )


# ── Device events ────────────────────────────────────────────────────────────
@dp.table(comment="Cleaned device/session events.")
@dp.expect_or_drop("valid_event", "client_id IS NOT NULL AND event_ts IS NOT NULL")
def silver_device_events():
    return (
        dp.read(f"{catalog}.{bronze}.bronze_device_events")
        .select(
            "client_id", "device_id", "os", "event_type", "ip",
            F.col("event_ts").cast("timestamp").alias("event_ts"),
        )
        .withColumn("event_date", F.to_date("event_ts"))
    )


# ── Notifications ────────────────────────────────────────────────────────────
@dp.table(comment="Cleaned notification deliveries.")
@dp.expect_or_drop("valid_notif", "notification_id IS NOT NULL AND client_id IS NOT NULL")
def silver_notifications():
    return (
        dp.read(f"{catalog}.{bronze}.bronze_notifications")
        .select(
            "notification_id",
            F.col("client_id").cast("int").alias("client_id"),
            "channel", "category",
            F.col("sent_ts").cast("timestamp").alias("sent_ts"),
            F.col("opened").cast("boolean").alias("opened"),
        )
        .withColumn("sent_date", F.to_date("sent_ts"))
    )
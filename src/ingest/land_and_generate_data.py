# Databricks notebook source
# ─────────────────────────────────────────────────────────────────────────────
# Land raw data into a Unity Catalog volume:
#   1. Download the Kaggle transactions/users/cards dataset.
#   2. Generate synthetic device + notification events keyed to real users.
# The medallion pipeline then reads these files with Auto Loader.
# ─────────────────────────────────────────────────────────────────────────────
from databricks.sdk.runtime import spark



dbutils.widgets.text("catalog", "neobank_dev")
dbutils.widgets.text("volume", "raw")
dbutils.widgets.text("sample_rows", "500000")

catalog = dbutils.widgets.get("catalog")
volume = dbutils.widgets.get("volume")
sample_rows = int(dbutils.widgets.get("sample_rows"))

vol_root = f"/Volumes/{catalog}/bronze/{volume}"

# COMMAND ----------
# Ensure catalog / schema / volume exist (idempotent).
for schema in ("bronze", "silver", "gold"):
    spark.sql(f"CREATE SCHEMA IF NOT EXISTS {catalog}.{schema}")
spark.sql(f"CREATE VOLUME IF NOT EXISTS {catalog}.bronze.{volume}")
for sub in ("transactions", "users", "cards", "mcc", "device_events", "notifications"):
    dbutils.fs.mkdirs(f"{vol_root}/{sub}")

# COMMAND ----------
# 1) Download the Kaggle dataset.
#    Requires Kaggle credentials. Locally: `pip install kagglehub` and set
#    KAGGLE_USERNAME / KAGGLE_KEY (or ~/.kaggle/kaggle.json).
#    Dataset: computingvictor/transactions-fraud-datasets
#      users_data.csv · cards_data.csv · transactions_data.csv · mcc_codes.json
try:
    import kagglehub
    src = kagglehub.dataset_download("computingvictor/transactions-fraud-datasets")
    import shutil, os
    for fname, sub in [
        ("users_data.csv", "users"),
        ("cards_data.csv", "cards"),
        ("transactions_data.csv", "transactions"),
        ("mcc_codes.json", "mcc"),
    ]:
        p = os.path.join(src, fname)
        if os.path.exists(p):
            shutil.copy(p, f"{vol_root}/{sub}/{fname}")
    print("Kaggle data landed in", vol_root)
except Exception as e:
    # Fallback: upload the CSVs to the volume manually via the UI, then re-run.
    print("Kaggle download skipped:", e)
    print(f"Upload the CSVs into {vol_root}/<users|cards|transactions|mcc>/ and re-run.")

# COMMAND ----------
# Optional: cap transactions volume while learning (keeps Free Edition quota safe).
if sample_rows > 0:
    import glob
    tx_files = glob.glob(f"{vol_root}/transactions/transactions_data.csv")
    if tx_files:
        df = spark.read.option("header", True).csv(f"{vol_root}/transactions/transactions_data.csv")
        (df.limit(sample_rows)
           .coalesce(1)
           .write.mode("overwrite").option("header", True)
           .csv(f"{vol_root}/transactions_sampled"))
        dbutils.fs.rm(f"{vol_root}/transactions", recurse=True)
        dbutils.fs.mv(f"{vol_root}/transactions_sampled", f"{vol_root}/transactions", recurse=True)
        print(f"Capped transactions at {sample_rows:,} rows")

# COMMAND ----------
# 2) Generate synthetic device + notification events keyed to real client_ids.
from pyspark.sql import functions as F

users = (spark.read.option("header", True)
         .csv(f"{vol_root}/users/users_data.csv")
         .select(F.col("id").cast("int").alias("client_id"))
         .where("client_id is not null"))

# Device login/session events (one row per session).
devices = (users
    .withColumn("n", (F.rand(7) * 8 + 1).cast("int"))
    .withColumn("s", F.explode(F.expr("sequence(1, n)")))
    .withColumn("device_id", F.concat(F.lit("dev_"), (F.rand(1) * 5000).cast("int")))
    .withColumn("os", F.element_at(F.array(F.lit("iOS"), F.lit("Android"), F.lit("Web")),
                                   (F.rand(2) * 3 + 1).cast("int")))
    .withColumn("event_type", F.element_at(
        F.array(F.lit("login"), F.lit("session"), F.lit("logout"), F.lit("password_reset")),
        (F.rand(3) * 4 + 1).cast("int")))
    .withColumn("ip", F.concat_ws(".", (F.rand(4) * 255).cast("int"), (F.rand(5) * 255).cast("int"),
                                  (F.rand(6) * 255).cast("int"), (F.rand(8) * 255).cast("int")))
    .withColumn("event_ts", F.expr("timestamp(current_timestamp() - make_interval(0,0,0,cast(rand()*90 as int),cast(rand()*24 as int),0,0))"))
    .select("client_id", "device_id", "os", "event_type", "ip", "event_ts"))

devices.write.mode("overwrite").json(f"{vol_root}/device_events")

# Notification events (push/email/SMS with an opened flag).
notifs = (users
    .withColumn("n", (F.rand(11) * 12 + 1).cast("int"))
    .withColumn("s", F.explode(F.expr("sequence(1, n)")))
    .withColumn("notification_id", F.expr("uuid()"))
    .withColumn("channel", F.element_at(F.array(F.lit("push"), F.lit("email"), F.lit("sms")),
                                        (F.rand(12) * 3 + 1).cast("int")))
    .withColumn("category", F.element_at(
        F.array(F.lit("transaction_alert"), F.lit("marketing"), F.lit("security"), F.lit("statement")),
        (F.rand(13) * 4 + 1).cast("int")))
    .withColumn("sent_ts", F.expr("timestamp(current_timestamp() - make_interval(0,0,0,cast(rand()*90 as int),0,0,0))"))
    .withColumn("opened", (F.rand(14) < 0.42))
    .select("notification_id", "client_id", "channel", "category", "sent_ts", "opened"))

notifs.write.mode("overwrite").json(f"{vol_root}/notifications")

print("Synthetic device + notification events generated.")
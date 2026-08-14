# ─────────────────────────────────────────────────────────────────────────────
# Land raw data into a Unity Catalog volume:
#   1. Download the Kaggle transactions/users/cards dataset.
#   2. Generate synthetic device + notification events keyed to real users.
# The medallion pipeline then reads these files with Auto Loader.
# ─────────────────────────────────────────────────────────────────────────────
import argparse
import os
import shutil

from pyspark.sql import functions as F

from neobank_datalake.db_context import get_spark

spark = get_spark()

parser = argparse.ArgumentParser()
parser.add_argument("--catalog", required=True)
parser.add_argument("--volume", required=True)
parser.add_argument("--sample-rows", type=int, default=0)   # default avoids `None > 0`
args = parser.parse_args()

catalog = args.catalog
volume = args.volume
sample_rows = args.sample_rows

vol_root = f"/Volumes/{catalog}/bronze/{volume}"

# Ensure catalog / schema / volume exist (idempotent).
for schema in ("bronze", "silver", "gold"):
    spark.sql(f"CREATE SCHEMA IF NOT EXISTS {catalog}.{schema}")
spark.sql(f"CREATE VOLUME IF NOT EXISTS {catalog}.bronze.{volume}")

# UC volumes are ordinary local paths — use os/shutil, never dbutils.fs.
for sub in ("transactions", "users", "cards", "mcc", "device_events", "notifications"):
    os.makedirs(f"{vol_root}/{sub}", exist_ok=True)

# 1) Download the Kaggle dataset.
#    Requires Kaggle credentials. Locally: `pip install kagglehub` and set
#    KAGGLE_USERNAME / KAGGLE_KEY (or ~/.kaggle/kaggle.json).
try:
    import kagglehub
    src = kagglehub.dataset_download("computingvictor/transactions-fraud-datasets")
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

# Optional: cap transactions volume while learning (keeps Free Edition quota safe).
if sample_rows > 0:
    tx_csv = f"{vol_root}/transactions/transactions_data.csv"
    if os.path.exists(tx_csv):
        df = spark.read.option("header", True).csv(tx_csv)
        (df.limit(sample_rows)
           .coalesce(1)
           .write.mode("overwrite").option("header", True)
           .csv(f"{vol_root}/transactions_sampled"))
        shutil.rmtree(f"{vol_root}/transactions")
        shutil.move(f"{vol_root}/transactions_sampled", f"{vol_root}/transactions")
        print(f"Capped transactions at {sample_rows:,} rows")

# 2) Generate synthetic device + notification events keyed to real client_ids.
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
# ─────────────────────────────────────────────────────────────────────────────
# SEMANTIC LAYER — Unity Catalog metric views (Business Semantics).
# A metric view defines DIMENSIONS (what you slice by) and MEASURES (the numbers)
# once. Every consumer — SQL, dashboards, notebooks, Genie — queries the same
# governed definition with MEASURE(), so revenue means the same thing everywhere.
# ─────────────────────────────────────────────────────────────────────────────
import argparse

# from neobank_datalake.db_context import get_spark

parser = argparse.ArgumentParser()
parser.add_argument("--catalog", required=True)
parser.add_argument("--gold-schema")
args = parser.parse_args()

# spark = get_spark()

catalog = args.catalog
gold = args.gold_schema

# Metric view 1 — Transactions & spend.
spark.sql(f"""
CREATE OR REPLACE VIEW {catalog}.{gold}.mv_transactions
WITH METRICS
LANGUAGE YAML
AS $$
version: "0.1"
source: {catalog}.{gold}.fact_transactions
joins:
  - name: user
    source: {catalog}.{gold}.dim_users
    on: source.client_id = user.client_id
  - name: merchant
    source: {catalog}.{gold}.dim_merchant
    on: source.merchant_id = merchant.merchant_id
dimensions:
  - name: Transaction date
    expr: transaction_date
  - name: Merchant category
    expr: merchant.mcc_description
  - name: Income band
    expr: user.income_band
  - name: Credit band
    expr: user.credit_band
  - name: Entry mode
    expr: use_chip
measures:
  - name: Total spend
    expr: SUM(amount_usd)
  - name: Transaction count
    expr: COUNT(1)
  - name: Active customers
    expr: COUNT(DISTINCT client_id)
  - name: Average transaction value
    expr: SUM(amount_usd) / COUNT(1)
  - name: Decline rate
    expr: SUM(CASE WHEN is_declined THEN 1 ELSE 0 END) / COUNT(1)
  - name: Fraud rate
    expr: SUM(CASE WHEN is_fraud THEN 1 ELSE 0 END) / COUNT(1)
$$
""")

# Metric view 2 — Customer engagement (notifications + device activity).
spark.sql(f"""
CREATE OR REPLACE VIEW {catalog}.{gold}.mv_engagement
WITH METRICS
LANGUAGE YAML
AS $$
version: "0.1"
source: {catalog}.{gold}.fact_notifications
joins:
  - name: user
    source: {catalog}.{gold}.dim_users
    on: source.client_id = user.client_id
dimensions:
  - name: Sent date
    expr: sent_date
  - name: Channel
    expr: channel
  - name: Category
    expr: category
  - name: Income band
    expr: user.income_band
measures:
  - name: Notifications sent
    expr: COUNT(1)
  - name: Open rate
    expr: SUM(CASE WHEN opened THEN 1 ELSE 0 END) / COUNT(1)
  - name: Reached customers
    expr: COUNT(DISTINCT client_id)
$$
""")

# Query the governed metrics with MEASURE() — grouped by ANY dimension at runtime.
# print("Spend by merchant category:")
# spark.sql(f"""
#   SELECT `Merchant category`, MEASURE(`Total spend`) AS spend,
#          MEASURE(`Active customers`) AS customers
#   FROM {catalog}.{gold}.mv_transactions
#   GROUP BY `Merchant category`
#   ORDER BY spend DESC
#   LIMIT 10
# """).show(truncate=False)

# print("Notification open rate by channel:")
# spark.sql(f"""
#   SELECT `Channel`, MEASURE(`Open rate`) AS open_rate,
#          MEASURE(`Notifications sent`) AS sent
#   FROM {catalog}.{gold}.mv_engagement
#   GROUP BY `Channel`
#   ORDER BY sent DESC
# """).show(truncate=False)

# TIP: point an AI/BI Genie space at these two metric views. Because the KPIs are
# governed, natural-language questions ("open rate for push last month?") resolve
# to the exact same definitions used by every dashboard.
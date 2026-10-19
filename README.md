# 🏦 Neobank Lakehouse

> An end-to-end, production-shaped analytics platform for a digital-only bank —
> built entirely as code with **Databricks Asset Bundles**, **Lakeflow Declarative
> Pipelines**, and the **Unity Catalog** governed semantic layer.

This project takes raw neobank data — customers, cards, transactions, device
activity, and notifications — and turns it into a governed, query-able star schema
with consistent business KPIs that any tool (SQL, dashboards, AI/BI Genie) can
consume. It's designed as a learning capstone: every layer maps to a real
capability a data team ships in practice, and everything (infrastructure, governance
and code) is deployed from this repo with Terraform and the bundle.

---

## Table of contents

1. [What this project demonstrates](#what-this-project-demonstrates)
2. [Architecture](#architecture)
3. [Core concepts: jobs, tasks, pipelines & triggers](#core-concepts-jobs-tasks-pipelines--triggers)
4. [Data model](#data-model)
5. [The dataset](#the-dataset)
6. [Repository structure](#repository-structure)
7. [Prerequisites](#prerequisites)
8. [Getting started](#getting-started)
9. [How a run flows end to end](#how-a-run-flows-end-to-end)
10. [The semantic layer (business metrics)](#the-semantic-layer-business-metrics)
11. [Configuration](#configuration)
12. [Free Edition notes](#free-edition--serverless-notes)
13. [Troubleshooting](#troubleshooting)
14. [Extending the project](#extending-the-project)
15. [References](#references)

---

## What this project demonstrates

| Capability | Implemented in |
|---|---|
| **Asset Bundles** — jobs, pipelines and dashboards as code, dev/prod targets | `databricks.yaml`, `resources/` |
| **Terraform** — catalog, schemas, grants, identities; shared + per-env layers | `terraform/` |
| **Scalable incremental ingestion** — Auto Loader (`cloudFiles`) | `src/pipelines/bronze.py` |
| **Medallion architecture** — bronze → silver → gold | `src/pipelines/` |
| **Data-quality enforcement** — expectations that drop & count bad rows | `src/pipelines/silver.py` |
| **Dimensional modeling** — conformed dimensions + fact tables | `src/pipelines/gold.py` |
| **Governed semantic layer** — Unity Catalog metric views, `MEASURE()` | `src/metrics/create_metric_views.py` |
| **Orchestration** — a job chaining ingest → pipeline → tags → metrics | `resources/jobs.yaml` |
| **ABAC governance** — governed tags, column masks, row filters | `src/governance/`, `src/udf/`, `terraform/modules/uc_abac_policies` |
| **CI/CD** — validate on PR, deploy prod as a service principal | `.github/workflows/bundle-deploy.yml` |
| **Lineage** — automatic via Unity Catalog | (platform) |
| **Natural-language analytics** — Genie grounded on the metric views | (see semantic layer) |

The point isn't just to move data — it's to move it in a way that stays
**consistent, governed, and query-able** as it scales.

---

## Architecture

Raw files land in a Unity Catalog volume, flow through three refinement layers,
and surface as governed metrics:

```
   Kaggle dataset                        Synthetic events
   users · cards · transactions          devices · notifications
              \                              /
               ▼                            ▼
          ┌──────────────────────────────────────┐
          │   Unity Catalog volume (raw files)    │
          └──────────────────────────────────────┘
                          │  Auto Loader — incremental, scales to millions of files
                          ▼
   ┌───────────────────────────────────────────────────────────────┐
   │  BRONZE   raw · append-only · schema-tracked                   │
   │     ▼                                                          │
   │  SILVER   typed · deduplicated · conformed · quality-checked   │
   │     ▼                                                          │
   │  GOLD     star schema — fact tables + conformed dimensions     │
   └───────────────────────────────────────────────────────────────┘
                          │
                          ▼
          ┌──────────────────────────────────────┐
          │  Metric views (business semantics)    │
          │  define each KPI once → MEASURE()     │
          └──────────────────────────────────────┘
                 │            │            │
                 ▼            ▼            ▼
            AI/BI Genie   Dashboards   SQL / notebooks
```

**Why medallion?** Each layer has one job. Bronze preserves raw truth (so you can
always reprocess). Silver makes data *correct* (types, dedup, quality). Gold makes
it *fast to query* (star schema). Keeping these separate means a bug in
transformation logic never corrupts your raw record, and analysts always query the
clean, modeled layer — never the mess.

---

## Core concepts: jobs, tasks, pipelines & triggers

Understanding how the pieces relate is the key to reading this project.

### The hierarchy

- **Job** — the orchestrator you schedule. It coordinates work but does none itself.
  (Databricks now calls these *Lakeflow Jobs*; older docs say "Workflows.")
- **Task** — one step inside a job. Every task has a **type** that decides what it
  does: `notebook_task`, `python_wheel_task`, `sql_task`, `pipeline_task`,
  `run_job_task`, plus control types like `condition_task` and `for_each_task`.
- **Pipeline** — a *separate* object (a Lakeflow Declarative Pipeline). It holds its
  own graph of tables/materialized views. A job reaches it through one task type:
  `pipeline_task`.

```
  JOB neobank_daily  (schedule / manual / CLI / file-arrival trigger)
   └── TASK land_data           (spark_python_task)
        └── depends_on ──► TASK build_medallion   (pipeline_task) ──┐
                            ├── depends_on ──► TASK tag_gold_columns    (sql_task)
                            └── depends_on ──► TASK build_metrics_views (spark_python_task)
                                                                     │ triggers
                                                                     ▼
  PIPELINE neobank_medallion
   └── bronze ──► silver ──► gold   (order auto-inferred from dlt.read() lineage)
```

### The one insight that clears up the confusion — two kinds of DAG

There are two dependency graphs here, and they work in **opposite** ways:

- **The job's task graph is orchestration (imperative).** *You* write the order with
  `depends_on`. No `depends_on` → tasks run in parallel. You are in control.
- **The pipeline's table graph is dataflow (declarative).** You do **not** write
  `depends_on`. Because `silver_transactions` calls `dlt.read("bronze_transactions")`,
  the pipeline *infers* that bronze runs first. You declare *what* the tables are;
  the engine decides *when*.

Orchestration on the outside, dataflow on the inside.

### How each thing is triggered

| Level | Started by |
|---|---|
| **Job** | Schedule (cron), manual run, CLI (`databricks bundle run <job>`), API, file-arrival or table-update trigger, continuous mode, or another job (`run_job_task`). |
| **Task** | Its `depends_on` — runs when upstream tasks finish (subject to `run_if`). First task(s) start when the job starts. |
| **Pipeline** | A job's `pipeline_task`, its own schedule, continuous mode, manual run, or CLI (`databricks bundle run <pipeline>`). |
| **Table in a pipeline** | Never by hand — order comes from `dlt.read()` lineage. |

### How the link is wired in the bundle

Jobs and pipelines are both `resources:`, connected by a single substitution that
injects the pipeline's ID into the job task at deploy time:

```yaml
tasks:
  - task_key: build_medallion
    pipeline_task:
      pipeline_id: ${resources.pipelines.neobank_medallion.id}   # ← the wire
    depends_on:
      - task_key: land_data                                      # ← order you control
```

You never hardcode an ID — the reference resolves itself on every deploy.

---

## Data model

### Sources

- **Real (Kaggle):** `users_data.csv`, `cards_data.csv`, `transactions_data.csv`
  (≈13M rows), `mcc_codes.json`.
- **Synthetic (generated):** device/session events and notification deliveries,
  keyed to the real `client_id`s so they join cleanly to actual customers.

### Gold star schema

```
        dim_users ─────┐              ┌───── dim_merchant
                       ├── fact_transactions ──┐
        dim_cards ─────┘                       └── dim_date
        dim_users ────────── fact_notifications
        dim_users ────────── fact_device_activity
```

| Table | Grain (one row per…) | Key columns |
|---|---|---|
| `fact_transactions` | transaction | `amount_usd`, `is_declined`, `mcc`, `is_fraud` |
| `fact_notifications` | notification sent | `channel`, `category`, `opened` |
| `fact_device_activity` | device session/event | `os`, `event_type`, `event_ts` |
| `dim_users` | customer | `income_band`, `credit_band` |
| `dim_cards` | card | `card_brand`, `card_type`, `credit_limit` |
| `dim_merchant` | merchant | `mcc_description`, `merchant_city` |
| `dim_date` | calendar day | `year`, `month`, `is_weekend` |

Facts hold the *numbers and foreign keys*; dimensions hold the *descriptive
attributes you slice by*. This is exactly the shape metric views and BI tools
expect — fast joins, unambiguous grain.

---

## The dataset

Core data: **[`computingvictor/transactions-fraud-datasets`](https://www.kaggle.com/datasets/computingvictor/transactions-fraud-datasets)**
on Kaggle. It's realistic and large (~13M transactions with users, cards, and MCC
merchant codes), which makes it ideal for practicing scale.

Because it has no device or notification streams, the ingestion step generates
those synthetically — giving you all four requested domains (devices, users,
transactions, notifications) with believable relationships.

> **Volume control:** the `sample_rows` variable caps transactions (default
> `500000`) so you don't exhaust Free Edition compute quota while learning. Set it
> to `0` on a real workspace to process the full dataset.

---

## Repository structure

```
neobank_lakehouse/
├── databricks.yaml                    # Bundle: name, wheel artifact, variables, dev/prod targets
├── resources/
│   ├── pipelines.yaml                 # Lakeflow declarative pipeline (the medallion)
│   ├── jobs.yaml                      # neobank_daily + neobank_security_functions (UDFs)
│   └── neobank_analytics.dashboard.yaml
├── src/
│   ├── ingest/land_and_generate_data.py   # Kaggle download + synthetic events
│   ├── pipelines/                     # bronze.py · silver.py · gold.py
│   ├── metrics/create_metric_views.py # Unity Catalog metric views (semantic layer)
│   ├── governance/tag_gold_columns.sql    # governed tags on sensitive gold columns
│   ├── udf/                           # mask / row-filter UDFs for the ABAC policies
│   ├── neobank_datalake/              # shared Python package, built as the wheel
│   └── dashboards/neobank_analytics.lvdash.json  # AI/BI dashboard (dev copy)
├── terraform/                         # see "Deploy order: Terraform + bundle"
│   ├── modules/                       # uc_catalog · uc_abac_policies · neobank_env
│   ├── shared/                        # workspace-wide objects, one state
│   └── envs/{dev,prod}/               # one root and state per environment
├── tests/                             # pytest (unit + integration markers)
├── .github/workflows/bundle-deploy.yml
├── .envrc / .env                      # TARGET_ENV drives both tools (direnv)
└── Makefile                           # tests, tf-* and deploy targets
```

---

## Prerequisites

- **Databricks CLI** v0.218.0 or newer — check with `databricks --version`.
- **Terraform** 1.5 or newer, **[direnv](https://direnv.net/)** and **[uv](https://docs.astral.sh/uv/)**
  (the bundle builds the wheel with `uv build`).
- A **Unity Catalog-enabled** workspace (Databricks Free Edition qualifies).
- The account groups `data-engineers`, `pci-readers`, `pii-readers`,
  `global-analysts` and the service principal `sp-metabase-reader`, created in the
  UI (Terraform looks them up; see [Free Edition notes](#free-edition--serverless-notes)).
- **Kaggle credentials** for the download step — set `KAGGLE_USERNAME` /
  `KAGGLE_KEY`, or upload the CSVs to the volume manually (the ingest script
  supports both paths).

---

## Getting started

Follow this order every time. Only `run` consumes compute — everything else is free,
so validate and plan as often as you like.

```bash
# 1. Authenticate (once per machine). .envrc selects the profile
#    (DATABRICKS_CONFIG_PROFILE=free-edition-workspace)
databricks auth login --host https://<workspace>.cloud.databricks.com \
  --profile free-edition-workspace
databricks current-user me           # verify

# 2. Pick the environment: TARGET_ENV=dev in .env, plus TF_VAR_slack_webhook_url
direnv allow

# 3. Infrastructure first: the bundle expects the catalog, schemas and volume
#    (first time on a workspace: follow "Deploy order" below)
make tf-shared-plan && make tf-plan

# 4. Validate & preview the bundle — FREE, no compute
databricks bundle validate
databricks bundle plan

# 5. Deploy to your dev sandbox — FREE
make deploy

# 6. Run the full workflow — THIS uses compute
databricks bundle run neobank_daily

# 7. Inspect
databricks bundle summary
databricks bundle open neobank_medallion     # watch the pipeline DAG build

# 8. Clean up the bundle's jobs/pipelines (Terraform-owned objects stay)
databricks bundle destroy
```

In `dev` mode, every resource is prefixed `[dev <you>]` and schedules are paused, so
you can iterate freely without touching anything shared. Prod is deployed by CI, not
from your machine (see [CI/CD](#cicd)).

### Deploy order: Terraform + bundle

Each object has exactly one owner, and each tool owns what changes with it:

| Owner | What | Why |
|---|---|---|
| `terraform/shared` (once per workspace) | `sp-github-cicd` + secrets, notification destinations, governed tag definitions (`pci`, `pii`, `region_sensitive`), warehouse permissions | Exist once in the workspace no matter how many envs; tag keys are account-wide |
| `terraform/envs/<env>` (once per env) | catalog `neobank_<env>`, schemas, volume, grants, ABAC policies | Platform and governance rules per env; change rarely |
| Bundle | pipelines, jobs, gold tables, mask/row-filter UDFs, **column tag assignments** (`src/governance/tag_gold_columns.sql`) | Change with the data model; a new sensitive column is tagged in the same PR that adds it |

The tools only reference each other **by name** (`neobank_<env>`, `slack_neobank`,
`sp-github-cicd`), never by ID or shared state. Rules that keep them apart:

- The bundle never creates UC containers (no `catalogs:`/`schemas:`/`volumes:`
  resources, no `CREATE SCHEMA` in jobs). `land_data` fails fast if the volume is missing.
- No grants outside Terraform on Terraform-owned securables: `databricks_grants` is
  authoritative and revokes them on the next apply.
- No per-env copies of workspace-wide objects; add them to `terraform/shared`.

```
terraform/
  modules/
    uc_catalog/        generic: catalog, schemas, volumes, authoritative grants
    uc_abac_policies/  generic: tag-driven column masks / row filters on a schema
    neobank_env/       composition: neobank's schemas, principals and policies for one env
  shared/              root, own state: workspace-wide objects
  envs/dev, envs/prod  thin roots, own state each: module "neobank" { env = "<env>" }
```

**Choosing the environment.** Both tools read the target from `.env` via
[direnv](https://direnv.net/). Set `TARGET_ENV=dev` (or `prod`) in `.env`; `.envrc`
derives everything else from it:

| Variable | Value | Read by |
|---|---|---|
| `DATABRICKS_BUNDLE_TARGET` | `$TARGET_ENV` | bundle (replaces `-t`) |
| `BUNDLE_VAR_catalog` | `neobank_$TARGET_ENV` | bundle `${var.catalog}` |
| `TF_ENV_DIR` | `terraform/envs/$TARGET_ENV` | `make tf-plan` / `make tf-apply` |

Run `direnv allow` once, and again after editing `.envrc`. Terraform picks the env by
directory, so each env has its own state and dev and prod can't overwrite each other.

Unity Catalog rejects a policy whose function doesn't exist yet, so the policies
wait for the UDFs. Column tags are set by the `tag_gold_columns` task in
`neobank_daily`, right after the pipeline builds the tables. On a fresh workspace,
deploy in this order:

```bash
# 0. Once per workspace: identities, destinations, tag definitions
#    (copy terraform/shared/terraform.tfvars.example to terraform.tfvars first)
make tf-shared-apply

# 1. Once per environment: create the catalog with SQL (Free Edition's Default
#    Storage only works through SQL/UI, not the catalog API). The import block in
#    terraform/envs/<env>/main.tf adopts it; plan fails until it exists.
#    CREATE CATALOG IF NOT EXISTS neobank_prod;       -- in the SQL editor

# 2. Base infrastructure: schemas, volume, grants (ABAC policies are skipped)
make tf-apply

# 3. Deploy the bundle and create the mask / row-filter UDFs
make deploy
databricks bundle run neobank_security_functions

# 4. ABAC policies, which can now find their UDFs: set
#    enable_abac_policies = true in terraform/envs/<env>/terraform.tfvars
make tf-apply

# 5. Build the tables; tag_gold_columns tags them and the policies apply at once
databricks bundle run neobank_daily       # uses compute
```

Steps 0, 1, 2 and 4 are one-time per workspace/environment. After that, a new
sensitive column needs only a change to `tag_gold_columns.sql`.

See [`docs/ABAC_TAGS_POLICIES.md` §5](docs/ABAC_TAGS_POLICIES.md) for why the
dependency chain looks like this.

State is local and gitignored (it holds SP secrets). Before running Terraform in CI,
move each root to a remote backend (see the comment in each `versions.tf`).

Rerun `neobank_security_functions` whenever you change a file in `src/udf/`. The
UDFs use `CREATE OR REPLACE`, so reruns are safe. Never drop or rename a UDF while
a policy still references it: remove the policy in Terraform first, then the
function.

> **Free Edition:** `pci-readers`, `pii-readers` and `global-analysts` are
> account-level groups, so Terraform can't manage who is in them. Add members by
> hand under Settings → Identity and access → Groups.

### CI/CD

`.github/workflows/bundle-deploy.yml` runs on every PR and push to `main`:

| Job | When | What |
|---|---|---|
| `validate-dev` | every PR and push | `databricks bundle validate` against the `dev` GitHub environment |
| `deploy-prod` | push to `main`, and repo variable `PROD_DEPLOY_ENABLED=true` | `bundle validate` + `bundle deploy` as `sp-github-cicd`, one at a time |

Both GitHub environments (`dev`, `prod`) need the secrets `DATABRICKS_HOST`,
`DATABRICKS_CLIENT_ID`, `DATABRICKS_CLIENT_SECRET` and the variable
`DATABRICKS_BUNDLE_TARGET`. Take the client ID and secret from Terraform:

```bash
terraform -chdir=terraform/shared output sp_cicd_client_id
terraform -chdir=terraform/shared output -raw sp_cicd_client_secret
```

**Dashboard per env.** A metric-view dataset needs a fully qualified `asset_name`;
`dataset_catalog` / `dataset_schema` don't apply to it. So
`src/dashboards/neobank_analytics.lvdash.json` is the dev copy you edit, and `make dashboards
TARGET_ENV=prod` renders `build/dashboards/neobank_analytics.prod.lvdash.json` with
`neobank_prod` names (gitignored, CI runs it before deploy). After editing the
dashboard in the dev workspace, pull it back with
`databricks bundle generate dashboard --resource neobank_analytics --force`.

CI deploys only the bundle. Terraform is still applied locally, so run
`make tf-apply` for prod (with `TARGET_ENV=prod`) before enabling `deploy-prod`.

---

## How a run flows end to end

When you run `neobank_daily`, here's the sequence (and which concept each step
illustrates):

1. **`land_data`** (`spark_python_task`) downloads the Kaggle files into the Unity
   Catalog volume and generates synthetic device + notification events. It fails
   fast if the volume doesn't exist yet (run `make tf-apply` first).
2. **`build_medallion`** (`pipeline_task`) — because it `depends_on` `land_data`, it
   waits for step 1, then *triggers the entire pipeline*. Inside the pipeline, bronze
   → silver → gold order themselves from `dlt.read()` lineage (no `depends_on`).
3. **`tag_gold_columns`** (`sql_task`) — tags the sensitive gold columns, so the
   ABAC policies mask / filter them straight away.
4. **`build_metrics_views`** (`spark_python_task`) — runs in parallel with step 3 and
   creates the governed metric views in the `metrics_view` schema. The views read
   from `gold`, but live in their own schema so BI access can be granted on
   `metrics_view` alone.

To test just one part:

```bash
databricks bundle run neobank_medallion                     # pipeline only
databricks bundle run --only build_medallion neobank_daily  # one task
```

---

## The semantic layer (business metrics)

Metric views define each KPI **once**, in YAML, governed in Unity Catalog. Every
consumer queries the same definition with `MEASURE()` and can group by any
dimension at runtime — so "total spend" means the same thing in every dashboard,
notebook, and Genie answer.

Two views are created:

- **`mv_transactions`** — total spend, transaction count, active customers, average
  transaction value, decline rate, fraud rate.
- **`mv_engagement`** — notifications sent, open rate, reached customers.

Query them like any table, but with `MEASURE()`:

```sql
-- Spend and active customers by merchant category
SELECT `Merchant category`,
       MEASURE(`Total spend`)      AS spend,
       MEASURE(`Active customers`) AS customers
FROM neobank_dev.metrics_view.mv_transactions
GROUP BY `Merchant category`
ORDER BY spend DESC;

-- Push vs email vs SMS open rate
SELECT `Channel`, MEASURE(`Open rate`) AS open_rate
FROM neobank_dev.metrics_view.mv_engagement
GROUP BY `Channel`;
```

Point an **AI/BI Genie** space at these two views and business users can ask
questions in plain language — *"push open rate for high-income customers last
month?"* — with answers grounded in the governed metrics, no SQL and no metric drift.

---

## Configuration

Bundle variables are defined in `databricks.yaml`. Override per target, or ad hoc
with `--var "name=value"`.

| Variable | Default (dev) | Purpose |
|---|---|---|
| `catalog` | `neobank_dev` | Unity Catalog catalog for all objects; set from `.envrc` (`BUNDLE_VAR_catalog`) |
| `bronze_schema` / `silver_schema` / `gold_schema` / `metrics_view_schema` | `bronze` / `silver` / `gold` / `metrics_view` | Schema per layer (created by Terraform) |
| `volume` | `raw` | Volume that holds landed raw files |
| `sample_rows` | `500000` | Cap on transactions loaded (`0` = all ~13M) |
| `warehouse_id` | Serverless Starter Warehouse | SQL tasks and the dashboard |
| `slack_destination_id` / `email_destination_id` | looked up by name | Notification destinations from `terraform/shared` |
| `cicd_sp_application_id` | looked up in `prod` | `sp-github-cicd`; prod `run_as` and root path |
| `oncall_email` | set in `databricks.yaml` | Email on `neobank_daily` failure |

Terraform inputs live in `terraform.tfvars` files (gitignored; copy the
`terraform.tfvars.example` next to each):

| Root | Inputs |
|---|---|
| `terraform/shared` | `warehouse_id`, `email_notification_addresses`, `slack_webhook_url` (via `TF_VAR_slack_webhook_url` in `.env`) |
| `terraform/envs/<env>` | `enable_abac_policies` |

**Targets:**

| Target | Mode | Catalog | Runs as | Deployed by |
|---|---|---|---|---|
| `dev` | `development` | `neobank_dev` | you | `make deploy` from your machine |
| `prod` | `production` | `neobank_prod` | `sp-github-cicd` | GitHub Actions on push to `main` |

Both targets load up to `sample_rows` (500k) transactions; override it for prod to
process the full dataset.

---

## Free Edition / serverless notes

- The pipeline is `serverless: true` — do **not** add classic clusters.
- **Deploy from your local machine**, not from inside the workspace (a serverless
  deploy can fail on a blocked Terraform download; if it does, run
  `databricks bundle deployment migrate`).
- Keep `sample_rows` modest while learning. The pipeline is incremental, so re-runs
  only process new data.
- If the Kaggle download can't reach the internet from serverless, upload the CSVs
  to the volume via the UI once, then re-run.
- Free Edition is free forever; the only limit is a daily compute quota that pauses
  compute (never deletes data) if exceeded.
- **Group membership is manual.** `data-engineers`, `pci-readers`, `pii-readers`
  and `global-analysts` are account-level groups, and Free Edition has no account
  console or account API, so Terraform can't add members (`databricks_group_member`
  fails with "can only be managed in account"). Add members under Settings →
  Identity and access → Groups. Service principals are different: Terraform can
  create them from the workspace (see `terraform/shared/service_principals.tf`).

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `error downloading Terraform … hashicorp.com` | Deploy locally, or run `databricks bundle deployment migrate`. |
| `land_data`: `/Volumes/neobank_<env>/bronze/raw not found` | Terraform hasn't been applied for this env: `make tf-apply`. |
| `terraform plan`: `Cannot import non-existent remote object` | Create the catalog first: `CREATE CATALOG IF NOT EXISTS neobank_<env>;` |
| `bundle validate -t prod`: dashboard file not found | Render it first: `make dashboards TARGET_ENV=prod`. |
| `lookup` fails for `slack_neobank` / `sp-github-cicd` | Apply `terraform/shared` first: `make tf-shared-apply`. |
| Auth failures | Regenerate token, re-run `databricks configure`, ensure host has no trailing slash. |
| `Cluster not found` / node type errors | Remove classic cluster config; the pipeline must be serverless. |
| Kaggle download fails | Set `KAGGLE_USERNAME`/`KAGGLE_KEY`, or upload CSVs to the volume manually and re-run. |
| Metric-view DDL rejected | `WITH METRICS LANGUAGE YAML` is a newer feature; verify syntax against the current business-semantics docs. |
| Pipeline task creates a duplicate | Ensure the job references `${resources.pipelines.neobank_medallion.id}`, not a hardcoded ID. |
| Compute suddenly unavailable | Free Edition daily quota reached — wait for reset; data is safe. |

---

## Extending the project

Great next exercises, roughly in order of impact:

- **Real fraud KPI** — join `train_fraud_labels.json` into `fact_transactions` so
  `Fraud rate` reflects true labels, then build a fraud dashboard.
- **SCD Type 2 history** on `dim_users` using `dlt.apply_changes` (AUTO CDC) to track
  how customer attributes change over time.
- **Engagement stickiness** — add a DAU/MAU window measure to `mv_engagement`.
- **Materialized metric views** for faster dashboards.
- **Agent metadata** (synonyms, display formats) so Genie speaks your business terms.
- **Alerting** — a Databricks Alert when `Decline rate` crosses a threshold.
- **File-arrival trigger** on the job so it runs when new data lands, not on a clock.

---

## References

- Databricks Asset Bundles: https://docs.databricks.com/aws/en/dev-tools/bundles/
- Bundle CLI commands: https://docs.databricks.com/aws/en/dev-tools/cli/bundle-commands
- Lakeflow Declarative Pipelines: https://docs.databricks.com/aws/en/dlt/
- Unity Catalog business semantics / metric views: https://docs.databricks.com/aws/en/business-semantics/
- Dataset: https://www.kaggle.com/datasets/computingvictor/transactions-fraud-datasets

---

*Built as a learning project to showcase the Databricks Lakehouse and Asset Bundles.
Not affiliated with any real financial institution; all data is public or synthetic.*
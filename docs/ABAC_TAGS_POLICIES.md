# ABAC, Tags & Policies — Gold Layer Governance

This document covers how to enforce data quality constraints, column masking, and
Attribute-Based Access Control (ABAC) on gold-layer tables built with **Lakeflow
Declarative Pipelines**, and how to manage tags/policies/masking functions with
**Terraform**.

---

## 1. Constraints in Declarative Pipelines

Pipeline-managed tables (materialized views, streaming tables) own their schema.
You cannot `ALTER TABLE` them externally and expect it to persist — constraints must
be declared **in the pipeline source**.

### 1.1 Row-level data quality → Expectations

Expectations validate/reject rows as they flow through the pipeline. This is the
*only* mechanism that actually enforces anything (schema-level constraints below are
informational only).

**SQL**

```sql
CREATE OR REFRESH MATERIALIZED VIEW gold.dim_users (
  CONSTRAINT valid_client_id EXPECT (client_id IS NOT NULL) ON VIOLATION FAIL UPDATE
)
AS SELECT * FROM silver.users;
```

**Python**

```python
from pyspark import pipelines as dp

@dp.materialized_view
@dp.expect_or_fail("valid_client_id", "client_id IS NOT NULL")
def dim_users():
    return spark.read.table("silver.users")
```

| Decorator | On violation | SQL equivalent |
|---|---|---|
| `@dp.expect` | Warn, row kept | no `ON VIOLATION` clause |
| `@dp.expect_or_drop` | Row dropped | `ON VIOLATION DROP ROW` |
| `@dp.expect_or_fail` | Pipeline update fails | `ON VIOLATION FAIL UPDATE` |
| `@dp.expect_all` / `_or_drop` / `_or_fail` | Same behaviors, multiple constraints via `{description: constraint}` dict | multiple `CONSTRAINT` clauses |

**Notes**
- Constraint expressions must be deterministic SQL booleans — no subqueries.
- `FAIL UPDATE` / `_or_fail` on a materialized view forces a **full refresh** every run (no incremental refresh).
- Metrics are queryable via the pipeline event log (`event_log()` table function) for dashboards/alerting.

### 1.2 Schema-level constraints → NOT NULL / informational PK / FK

Declared via the `schema=` argument (DDL string) or SQL column list. **Informational
only** — not enforced on write, used by the optimizer/catalog/BI tools.

**Requirements:** Unity Catalog–enabled pipeline. `NOT NULL` must be written
explicitly alongside `PRIMARY KEY` (not implied).

```python
@dp.materialized_view(
    name="gold.dim_users",
    schema="""
        client_id   STRING NOT NULL PRIMARY KEY,
        client_name STRING,
        email       STRING
    """
)
def dim_users():
    return spark.read.table("silver.users")
```

```python
@dp.table(
    name="gold.fact_orders",
    schema="""
        order_id  BIGINT NOT NULL PRIMARY KEY,
        client_id STRING,
        CONSTRAINT fk_client FOREIGN KEY (client_id) REFERENCES gold.dim_users(client_id)
    """
)
def fact_orders():
    return spark.readStream.table("silver.orders")
```

### 1.3 Important limitation: full schema required

**The `schema=`/`table_specification` must list every column returned by the
query — you cannot partially declare a schema (e.g. just the PK column) and let
the rest pass through inferred.**

| Scenario | Result |
|---|---|
| Schema has fewer columns than the query returns | ❌ Error |
| Schema has all columns the query returns, plus extra | ✅ Works (extras are `NULL`) |
| Schema matches exactly | ✅ Standard usage |

Workaround: generate the DDL string programmatically from the source table's schema,
injecting only the constraint clauses by hand:

```python
from pyspark.sql.types import StructType

def to_ddl_with_constraints(schema: StructType, pk_cols=None, not_null_cols=None):
    pk_cols = pk_cols or []
    not_null_cols = set(not_null_cols or []) | set(pk_cols)
    lines = []
    for f in schema.fields:
        line = f"{f.name} {f.dataType.simpleString().upper()}"
        if f.name in not_null_cols:
            line += " NOT NULL"
        lines.append(line)
    if pk_cols:
        lines.append(f"CONSTRAINT pk_{'_'.join(pk_cols)} PRIMARY KEY ({', '.join(pk_cols)})")
    return ",\n".join(lines)

ddl = to_ddl_with_constraints(spark.read.table("silver.users").schema, pk_cols=["client_id"])

@dp.materialized_view(name="gold.dim_users", schema=ddl)
def dim_users():
    return spark.read.table("silver.users")
```

Adding a PK to a table already published by a pipeline requires editing the
pipeline's schema definition and refreshing — not a bare `ALTER TABLE`.

---

## 2. Row filters & column masks via `@dp` (table-level, per-object)

Direct pipeline-native equivalent of `ALTER TABLE ... SET MASK`. Masking/filter
functions are still ordinary SQL UDFs created **outside** the pipeline
(`CREATE OR REPLACE FUNCTION`) — the pipeline only references them.

### SQL

```sql
CREATE OR REFRESH MATERIALIZED VIEW gold.dim_cards (
  card_id     BIGINT NOT NULL PRIMARY KEY,
  card_number BIGINT MASK gold.mask_card_number,
  cvv         INT    MASK gold.mask_cvv,
  client_id   STRING
)
WITH ROW FILTER gold.filter_active_cards ON (client_id)
AS SELECT * FROM silver.cards;
```

### Python

```python
@dp.materialized_view(
    name="gold.dim_cards",
    schema="""
        card_id     BIGINT NOT NULL PRIMARY KEY,
        card_number BIGINT MASK gold.mask_card_number,
        cvv         INT    MASK gold.mask_cvv,
        client_id   STRING
    """,
    row_filter="ROW FILTER gold.filter_active_cards ON (client_id)"
)
def dim_cards():
    return spark.read.table("silver.cards")
```

### Behavior notes

- Recent pipeline releases **merge** masks/filters rather than overwrite. Removing a
  `MASK` clause from the pipeline definition does **not** remove the mask from the
  table — you must explicitly drop it via `ALTER TABLE` / Catalog Explorer.
- Scope is per-table, per-column — same granularity as manual `ALTER TABLE`, just
  declared where the table is defined.

### When to use this vs. UC-native ABAC (§3)

| | Per-table `@dp` masks/filters | Unity Catalog ABAC |
|---|---|---|
| Where declared | In each pipeline dataset definition | Centrally, catalog/schema level |
| Applies to | Just that table | Every current + future tagged object |
| Maintenance | Touch every pipeline def when rules change | Change the policy once |
| Granularity | Per-column, explicit | Tag-driven, automatic inheritance |
| Best for | A few tables, tight coupling to pipeline logic | Org-wide PII/PCI governance at scale |

For a full gold-layer ABAC scheme spanning multiple tables, **UC-native ABAC is the
better long-term design** — masking logic stays the same, but you stop wiring
`MASK`/`ROW FILTER` into every pipeline definition.

---

## 3. Unity Catalog–native ABAC (governed tags + policies)

GA feature, decoupled from `@dp` entirely. Lives at catalog/schema/table level,
driven by governed tags. Tag once → policy auto-applies to every current and future
matching object, including pipeline-created tables.

### 3.1 Governed tags

```sql
CREATE GOVERNED TAG pii DESCRIPTION 'Contains personal data' VALUES ('true', 'false');
CREATE GOVERNED TAG pci DESCRIPTION 'Contains cardholder data' VALUES ('true');
```

### 3.2 Tagging columns

Tags are **pure catalog metadata** — not part of pipeline schema DDL, not settable
via `.withColumn` (that's a DataFrame data transform, has no access to catalog
metadata), and not a supported `schema=` column property (only `NOT NULL`,
`COMMENT`, `column_constraint`, `MASK` are).

```sql
ALTER TABLE gold.dim_users ALTER COLUMN address     SET TAGS ('pii' = 'true');
ALTER TABLE gold.dim_users ALTER COLUMN latitude    SET TAGS ('pii' = 'true');
ALTER TABLE gold.dim_cards ALTER COLUMN card_number SET TAGS ('pci' = 'true');
```

> Only **one column per `ALTER TABLE` statement** — unlike `COMMENT`, tag assignment
> doesn't support multiple columns in one command.

Since tags are never part of the pipeline's `schema=` definition, there is nothing
for the pipeline to "revert" on refresh — setting tags via `ALTER` is safe and
persists across pipeline redeploys.

### 3.3 ABAC policy

```sql
CREATE POLICY mask_pci_columns
ON SCHEMA gold
COLUMN MASK gold.mask_card_number
TO `account users`
EXCEPT `pci_readers`
FOR TABLES
MATCH COLUMNS hasTag('pci') AS card_col
ON COLUMN card_col;
```

Attach policies at the **highest applicable level** (catalog > schema > table) to
maximize governance efficiency — a schema-level policy covers every table beneath it,
tagged now or in the future.

---

## 4. Managing tags, policies & masking functions with Terraform

### 4.1 What Terraform natively supports

| Object | Resource | Native? |
|---|---|---|
| Governed tag definitions | `databricks_tag_policy` | ✅ |
| Tag assignment (catalog/schema/table/**column**) | `databricks_entity_tag_assignment` | ✅ |
| ABAC policy (row filter / column mask) | `databricks_policy_info` | ✅ |
| **Masking function SQL body** | — | ❌ No native resource |

```hcl
# Tag definitions
resource "databricks_tag_policy" "pii" {
  tag_key     = "pii"
  description = "Indicates column contains personal data"
  values { name = "true" }
  values { name = "false" }
}

resource "databricks_tag_policy" "pci" {
  tag_key     = "pci"
  description = "Indicates column contains cardholder data"
  values { name = "true" }
}

# Column tag assignment
resource "databricks_entity_tag_assignment" "card_number_pci" {
  entity_type = "columns"
  entity_name = "gold.dim_cards.card_number"
  tag_key     = "pci"
  tag_value   = "true"
  depends_on  = [databricks_tag_policy.pci]
}

resource "databricks_entity_tag_assignment" "address_pii" {
  entity_type = "columns"
  entity_name = "gold.dim_users.address"
  tag_key     = "pii"
  tag_value   = "true"
  depends_on  = [databricks_tag_policy.pii]
}

# ABAC policy
resource "databricks_policy_info" "mask_pci_columns" {
  name                  = "mask_pci_columns"
  on_securable_type     = "SCHEMA"
  on_securable_fullname = "gold"
  for_securable_type    = "TABLE"
  policy_type           = "POLICY_TYPE_COLUMN_MASK"

  to_principals     = ["account users"]
  except_principals = ["pci_readers"]

  match_columns {
    condition = "hasTag('pci')"
    alias     = "col"
  }

  column_mask {
    function_name = "gold.mask_generic_pci"
    on_column     = "col"
  }

  depends_on = [null_resource.mask_functions] # see 4.2
}
```

> `databricks_policy_info` attribute names are still evolving as ABAC is a newer GA
> feature — verify the exact block structure against current provider docs before
> implementing.

### 4.2 Masking functions: no native resource — workarounds

**Option A — `null_resource` + `local-exec`** (Statement Execution API)

```hcl
resource "null_resource" "mask_functions" {
  triggers = {
    sql_hash = sha256(file("${path.module}/sql/mask_card_number.sql"))
  }

  provisioner "local-exec" {
    command = <<-EOT
      databricks api post /api/2.0/sql/statements \
        --json '{
          "warehouse_id": "${var.sql_warehouse_id}",
          "statement": "${replace(file("${path.module}/sql/mask_card_number.sql"), "\n", " ")}"
        }'
    EOT
  }
}
```

Caveats: not idempotent-aware like a native resource (Terraform can't diff the SQL
body, only re-run on trigger change); manual edits in Catalog Explorer won't show up
in `plan`.

**Option B — Databricks Asset Bundles (DAB) own the function DDL** *(recommended)*

- DAB deploys the masking function SQL (via a deploy-triggered job task) alongside
  the pipeline.
- Terraform owns tags, tag assignments, and `policy_info` — referencing the function
  by fully-qualified name only.
- `databricks_sql_query` is **not** a fit here — it creates a saved query object for
  the UI, it does not execute DDL at `terraform apply`.

**Recommended split:**

```
Terraform (governance-as-code, changes rarely):
  ├── databricks_tag_policy              (pii, pci tag definitions)
  ├── databricks_entity_tag_assignment   (tag columns)
  └── databricks_policy_info             (ABAC policies)

DAB / SQL migration script (data-layer-as-code, evolves with schema):
  └── CREATE OR REPLACE FUNCTION gold.mask_*   (masking logic)
```

Rationale: masking functions are tightly coupled to table schemas and change
whenever those schemas do — that's pipeline/data-layer territory, not infra
territory.

---

## 5. Cross-tool sequencing ("chicken-and-egg")

### 5.1 It's a DAG, not a cycle

```
1. Schema (gold) must exist
        ↓
2. Masking function (gold.mask_card_number) must exist
        ↓
3. ABAC policy references the function by name
        ↓
4. Pipeline creates the table/columns
        ↓
5. Column gets tagged
        ↓
6. Policy (already active since step 3) picks it up automatically
```

The policy does **not** need the table to exist when created — it's a standing rule
evaluated dynamically at query time. So step 3 doesn't depend on step 4. The two
real requirements are: **function before policy**, and **table before tag** — two
independent chains, not a circular one.

### 5.2 Where the real friction is

Terraform and DAB don't share one `apply` graph — ordering across tools must be
enforced externally (CI/CD), since neither tool can see the other's state.

### 5.3 Fixes

**Option A — one ordered CI/CD pipeline** *(most common)*

```yaml
stages:
  - terraform apply -target=databricks_schema.gold
  - terraform apply -target=null_resource.mask_functions     # UDFs
  - terraform apply -target=databricks_policy_info.abac      # needs functions
  - databricks bundle deploy                                  # pipeline creates tables
  - terraform apply -target=databricks_entity_tag_assignment # tag new columns
```

Steps 1–3 run once (or when logic changes); steps 4–5 repeat on every
schema-changing deploy.

**Option B — collapse into a single Terraform graph**

Use `databricks_sql_table` (non-pipeline-managed) for specific gold tables and put
the whole chain — function, table, tags, policy — in one `terraform apply` with real
`depends_on`. Trade-off: loses Lakeflow's incremental refresh / expectations
machinery, so only sensible for tables that don't need pipeline semantics (e.g. a
small reference table), not core fact/dim tables.

**Option C — decouple tagging from deploy time**

Use Databricks' automatic **Data Classification** feature to scan and tag PII/PCI
columns on a schedule, independent of any deploy. Removes the tagging step from the
deploy critical path — the already-active ABAC policy protects columns as soon as
the tag lands. Trade-off: a window between table creation and classification running
where the column is untagged and unprotected — acceptable for many orgs, not for
strict compliance regimes needing protection atomic with table creation.

---

## 6. Summary decision guide

| Need | Mechanism |
|---|---|
| Reject/drop bad data as it flows in | `CONSTRAINT ... EXPECT ... ON VIOLATION ...` |
| Document PK/FK relationships for catalog/BI | Informational `PRIMARY KEY`/`FOREIGN KEY` in `schema=` (UC pipeline required) |
| Mask/filter a handful of specific pipeline tables | `@dp` `schema=` `MASK` clause + `row_filter=` |
| Org-wide PII/PCI governance across many tables | Unity Catalog ABAC (governed tags + `policy_info`) |
| Version-controlled, auditable governance rules | Terraform (`databricks_tag_policy`, `databricks_entity_tag_assignment`, `databricks_policy_info`) |
| Masking function logic tied to evolving schemas | DAB / SQL migration script, not Terraform |
| Cross-tool deploy ordering | Explicit staged CI/CD (function → policy → pipeline → tags) |

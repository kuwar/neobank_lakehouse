# Workspace Setup: Identities, Groups and Catalogs

The identities, groups and catalogs this project expects, why groups must be
**account-level** for Unity Catalog, and how to create them on Free Edition, where
some of it can't be done from Terraform. Do this before the first-time setup in
[MULTI_ENVIRONMENT_DEPLOYMENTS.md §5](MULTI_ENVIRONMENT_DEPLOYMENTS.md#5-first-time-setup-of-an-environment).

Related docs: [PERMISSIONS_REFERENCE.md](PERMISSIONS_REFERENCE.md) is the general
permissions reference; [DATA_GOVERNANCE.md](DATA_GOVERNANCE.md) covers the tags,
policies and masking functions, and what must exist before a policy is created.

---

## 1. This project in the account hierarchy

The metastore and the workspace are **siblings** under the account; a workspace is
*attached* to one metastore. Identities belong to the account and are assigned to
workspaces. For the full model and the three permission layers, see
[PERMISSIONS_REFERENCE.md §2–3](PERMISSIONS_REFERENCE.md#2-the-hierarchy-what-contains-what-and-which-is-the-root).

```
Account
├── Identities: kuwarsaurav21@gmail.com, sp-github-cicd, sp-metabase-reader,
│               data-engineers, pci-readers, pii-readers, global-analysts (← must live here)
├── Metastore 956334b6-...  (metastore_aws_us_east_2, Default Storage)
│     ├── governed tags: pci / pii / region_sensitive   (one set for every catalog)
│     ├── neobank_dev  → bronze / silver / gold / metrics_view
│     └── neobank_prod → bronze / silver / gold / metrics_view
└── Workspace 7474646559217195   (dev and prod share it)
      ├── attached to metastore 956334b6-...
      └── Serverless Starter Warehouse (dfc7731614511a53)
```

Dev and prod share this workspace and metastore, so identities and tag keys exist
once (`terraform/shared`; see
[MULTI_ENVIRONMENT_DEPLOYMENTS.md §1](MULTI_ENVIRONMENT_DEPLOYMENTS.md#1-the-model-one-workspace-three-layers)).

> **Don't confuse IDs.** `7474646559217195` is the *workspace* ID (the `?o=` in
> the URL). A *warehouse* ID is 16 hex chars, e.g. `dfc7731614511a53`
> (`databricks warehouses list`). `var.warehouse_id` needs the latter.

---

## 2. Catalogs on Default Storage (Free Edition)

A metastore may have an optional **storage root** — a default location for
managed tables of catalogs that don't specify their own. When a catalog is
created, the location is chosen as:

```
1. storage_root / MANAGED LOCATION passed?   → use it
2. Metastore has a storage root?             → use it
3. Otherwise                                 → error
```

Free Edition / Default Storage workspaces have no metastore storage root and no
user-owned external location. The UI silently falls back to Default Storage;
the catalog-create **API does not**, so `databricks_catalog` fails with:

```
Metastore storage root URL does not exist. Default Storage is enabled in your account.
```

**Workaround used in this repo:**

1. Create the catalog once per env with SQL (Default Storage):
   `CREATE CATALOG IF NOT EXISTS neobank_<env>;`
2. Each env root adopts it with an `import` block, so no manual `terraform import`
   is needed. Plan fails with "Cannot import non-existent remote object" until
   step 1 is done:

   ```hcl
   # terraform/envs/<env>/main.tf
   import {
     to = module.neobank.module.catalog.databricks_catalog.this
     id = "neobank_${local.env}"
   }
   ```

3. Stop Terraform from trying to replace it — Databricks fills `storage_root`
   on the imported catalog, and any diff on that attribute forces replacement:

```hcl
# terraform/modules/uc_catalog/main.tf
resource "databricks_catalog" "this" {
  name    = var.name
  comment = var.comment

  lifecycle {
    ignore_changes  = [storage_root, properties] # set server-side
    prevent_destroy = true                       # cannot be recreated from Terraform here
  }
}
```

Everything *inside* the catalog (schemas, volumes, grants, policies) is fully
manageable by Terraform.

---

## 3. Workspace-level vs account-level identities

### 3.1 The two kinds of group

| | Workspace-local group | Account group |
|---|---|---|
| Lives in | one workspace | the Databricks account |
| SCIM `meta.resourceType` | `WorkspaceGroup` | `Group` |
| Workspace entitlements, object ACLs | ✅ | ✅ (once assigned) |
| Unity Catalog grants | ❌ | ✅ |
| ABAC `to_principals` / `except_principals` | ❌ | ✅ |
| `is_account_group_member()` in masks / filters | ❌ always false | ✅ |
| Status | legacy (still supported) | recommended |

Check a group:

```bash
databricks groups get <group-id> -o json | grep -A2 meta
#   "meta": { "resourceType": "WorkspaceGroup" }   ← invisible to Unity Catalog
```

### 3.2 Why Unity Catalog can't see workspace-local groups

The metastore belongs to the **account**, not the workspace. When it resolves a
principal name in a grant or policy, it looks only at account identities. A
workspace-local `pci_readers` produces:

```
Error: failed to create policy_info
Could not find principal with name pci_readers.
```

The same applies at query time to `is_account_group_member('pci_readers')`: for a
workspace-local group it returns **false for everyone** — no error, the data is
just masked for members too. This repo avoids that call: the UDFs in `src/udf/`
only return the masked value, and exemptions are the policy's `except_principals`.

### 3.3 Why workspace-level identity exists at all

Before Unity Catalog, every workspace was an island: users, groups and Hive
metastore table ACLs were all per workspace. Unity Catalog and **identity
federation** moved governance and identity up to the account. Workspace-local
groups remain for backward compatibility (entitlements, object ACLs, legacy Hive
table ACLs), but there is nothing they can do that an assigned account group
cannot, and they cannot do Unity Catalog. Databricks recommends migrating them;
no removal date is relied on here.

### 3.4 Users and service principals behave differently

On an identity-federated workspace, creating a **user or service principal**
through the workspace API (e.g. `databricks_service_principal` with a workspace
provider) creates or links an **account-level** identity and assigns it to the
workspace. That is why `sp-metabase-reader` works in UC grants.

**Groups are the exception:** `databricks_group` with a workspace provider still
creates a legacy `WorkspaceGroup`.

| Identity | Create with | Usable in UC |
|---|---|---|
| User | workspace provider OK | ✅ |
| Service principal | workspace provider OK (use `application_id` as principal) | ✅ |
| Group | **account** provider, or workspace UI on Free Edition | ✅ only if account group |

---

## 4. How this repo handles it

### 4.1 Current state

| Item | How |
|---|---|
| `data-engineers`, `pci-readers`, `pii-readers`, `global-analysts` | account groups created in the UI; looked up with `data "databricks_group"` in `modules/neobank_env` |
| Group membership | by hand in the UI — Free Edition has no account API, so `databricks_group_member` fails |
| `sp-github-cicd` | created by Terraform (`terraform/shared/service_principals.tf`); an account-level identity through federation. Gets ASSIGN on the governed tags from `terraform/shared/governed_tags.tf` |
| `sp-metabase-reader` | created in the UI, looked up by name; Terraform only creates its OAuth secret |
| ABAC policy principals | data-source references, not string literals |
| `warehouse_id` (`terraform/shared/terraform.tfvars`) | the 16-hex warehouse ID, not the workspace ID |

### 4.2 Setting up groups

**On a paid account** — manage groups with an account-level provider:

```hcl
provider "databricks" {
  alias      = "account"
  host       = "https://accounts.cloud.databricks.com"
  account_id = var.databricks_account_id
}

resource "databricks_group" "pci_readers" {
  provider     = databricks.account
  display_name = "pci-readers"
}

resource "databricks_mws_permission_assignment" "pci_readers_ws" {
  provider     = databricks.account
  workspace_id = var.workspace_id
  principal_id = databricks_group.pci_readers.id
  permissions  = ["USER"]
}
```

These would go in `terraform/shared`: groups exist once per account, not per env.

**On Free Edition** (no account console / account API), which is what this repo does:

1. Create `data-engineers`, `pci-readers`, `pii-readers` and `global-analysts` in the
   workspace UI (**Settings → Identity and access → Groups**). On
   identity-federated workspaces the UI creates account groups.
2. Verify each: `databricks groups get <id>` → `"resourceType": "Group"`.
   Do this for the first group before creating the rest.
3. Add members in the same UI page.
4. Terraform only looks them up (group names are inputs of `modules/neobank_env`):

   ```hcl
   data "databricks_group" "this" {
     for_each     = var.groups      # pci_readers = "pci-readers", ...
     display_name = each.value
   }
   ```

5. Continue with the first-time setup in
   [MULTI_ENVIRONMENT_DEPLOYMENTS.md §5](MULTI_ENVIRONMENT_DEPLOYMENTS.md#5-first-time-setup-of-an-environment).

### 4.3 Rule of thumb

> If a group will ever appear in a Unity Catalog grant, an ABAC policy, or an
> `is_account_group_member()` call, it must be an **account group**.

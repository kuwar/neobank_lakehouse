# Multi-Environment Deployments

How `dev` and `prod` are built, kept apart and deployed: which tool owns what,
where each state lives, how one variable selects the environment, and the order
to run things in.

Related docs: [WORKSPACE_SETUP.md](WORKSPACE_SETUP.md) covers the groups,
service principals and catalogs to create first;
[DATA_GOVERNANCE.md](DATA_GOVERNANCE.md) explains why the governance objects are
split the way they are.

---

## 1. The model: one workspace, three layers

Dev and prod share one workspace and one metastore. They are separated by
**catalog** (`neobank_dev` / `neobank_prod`), by **identity** (you vs.
`sp-github-cicd`) and by **separate state** per tool and environment.

```
Workspace dbc-31fcc0ce-44e6  (shared by dev and prod)
│
├── terraform/shared ─────────── exists ONCE, used by both envs
│     sp-github-cicd (+ secret) · slack_neobank · neobank_email_notification
│     tag keys pci / pii / region_sensitive · warehouse permissions · Metabase secret
│
├── terraform/envs/dev ───────── catalog neobank_dev
│     schemas bronze/silver/gold/metrics_view · volume raw · grants · ABAC policies
├── terraform/envs/prod ──────── catalog neobank_prod  (same modules, same shape)
│
├── bundle target dev ────────── [dev you] jobs, pipeline, dashboard → neobank_dev
└── bundle target prod ───────── jobs, pipeline, dashboard (run as SP) → neobank_prod
```

| Layer | Owns | Changes | Deployed by | State |
|---|---|---|---|---|
| `terraform/shared` | objects that can exist only once per workspace: CI/CD SP, notification destinations, governed tag keys (account-wide), warehouse permissions | rarely | you: `make tf-shared-apply` | `terraform/shared/terraform.tfstate` |
| `terraform/envs/<env>` | catalog, schemas, volume, grants, ABAC policies | rarely | you: `make tf-apply` | `terraform/envs/<env>/terraform.tfstate` |
| Bundle (`databricks.yaml`) | pipeline, jobs, tables, UDFs, column tags, metric views, dashboard | with every data-model change | dev: you (`make deploy`); prod: GitHub Actions | workspace: `<root_path>/.bundle/neobank_lakehouse/<target>` |

That's four states, and none can overwrite another. Terraform selects state by
**directory**, the bundle by **target**.

### Terraform layout

```
terraform/
  modules/
    uc_catalog/        generic: catalog, schemas, volumes, authoritative grants
    uc_abac_policies/  generic: tag-driven column masks / row filters on a schema
    neobank_env/       composition: neobank's schemas, principals and policies for one env
  shared/              root: workspace-wide objects
  envs/dev, envs/prod  thin roots: module "neobank" { env = "<env>" } + catalog import
```

The generic modules know nothing about neobank. `neobank_env` holds the project
choices and takes only `env` and `enable_abac_policies`, so dev and prod can't
drift apart.

---

## 2. Rules that keep the layers from competing

1. **One owner per object.** The bundle never creates catalogs, schemas or volumes
   (no `catalogs:`/`schemas:`/`volumes:` resources, no `CREATE SCHEMA` in jobs);
   `land_data` fails fast if the volume is missing. Terraform never touches tables,
   UDFs or column tags.
2. **Grants only in Terraform.** `databricks_grants` is authoritative per securable:
   a grant made elsewhere on a Terraform-owned catalog or schema is revoked on the
   next apply.
3. **No per-env copies of workspace-wide objects.** If something can exist only
   once (an SP, a destination, a tag key, warehouse ACLs), it goes in
   `terraform/shared`.
4. **Connect by name, never by ID or state.** Each layer looks up what it needs:

```
terraform/shared        creates  sp-github-cicd, slack_neobank, tag key "pci"
     ▲ lookup by name                ▲ lookup by name           ▲ tag must exist
terraform/envs/<env>    grants to sp-github-cicd on neobank_<env>
bundle                  run_as sp-github-cicd · webhook → slack_neobank · tags columns "pci"
     ▼ writes into
neobank_<env>.bronze/silver/gold   (schemas from Terraform, tables from the pipeline)
```

The catalog name `neobank_<env>` is the contract between Terraform
(`modules/neobank_env`) and the bundle (`targets.<env>.variables.catalog`).

---

## 3. Selecting the environment: `TARGET_ENV`

Set `TARGET_ENV=dev` or `prod` in `.env`. `.envrc` (via [direnv](https://direnv.net/))
derives the rest; run `direnv allow` after editing it.

| Variable | Value | Read by |
|---|---|---|
| `TARGET_ENV` | `dev` / `prod` | the Makefile (CI sets it per job instead of `.env`) |
| `DATABRICKS_BUNDLE_TARGET` | `$TARGET_ENV` | plain `databricks bundle ...` commands (replaces `-t`) |
| `TF_ENV_DIR` | `terraform/envs/$TARGET_ENV` | informational; the Makefile derives the same path |

The catalog isn't an environment variable: each target in `databricks.yaml` sets
its own. Don't export `BUNDLE_VAR_catalog`, because it overrides every target, so
`make deploy TARGET_ENV=prod` would write into whatever catalog it names.

| Command | `TARGET_ENV=dev` | `TARGET_ENV=prod` |
|---|---|---|
| `make tf-plan` / `make tf-apply` | `terraform/envs/dev` | `terraform/envs/prod` |
| `make validate` | `bundle validate -t dev` | `bundle validate -t prod` |
| `make deploy` | `bundle deploy -t dev` | `bundle deploy -t prod` (normally CI) |
| `make dashboards` | run by `validate` / `deploy`; renders an unused dev copy | run by `validate` / `deploy`; renders `build/dashboards/neobank_analytics.prod.lvdash.json` |

A command-line value wins over `.env`: `make validate TARGET_ENV=prod` checks prod
without editing `.env`. CI runs the same `make validate` and `make deploy`.

`make tf-shared-plan` / `make tf-shared-apply` ignore `TARGET_ENV`.

### Terraform inputs

`terraform.tfvars` files are gitignored. Copy the `terraform.tfvars.example` next
to each root.

| Root | Inputs |
|---|---|
| `terraform/shared` | `warehouse_id`, `email_notification_addresses`, `slack_webhook_url` (as `TF_VAR_slack_webhook_url` in `.env`); GitHub: `prod_reviewers`, `prod_deploy_enabled`, `github_owner`, `github_repository` (defaults fit this repo), and `GITHUB_TOKEN` in `.env` (§7) |
| `terraform/envs/<env>` | `enable_abac_policies` |

---

## 4. Dev vs prod

| | dev | prod |
|---|---|---|
| Bundle mode | `development`: names prefixed `[dev <you>]`, schedules paused | `production`: real names, `neobank_daily` runs at 05:00 UTC |
| Catalog | `neobank_dev` | `neobank_prod` |
| Runs as | you | `sp-github-cicd` (`run_as`) |
| Bundle root path | `/Workspace/Users/<you>/.bundle/…/dev` | `/Workspace/Users/<sp-app-id>/.bundle/…/prod`, one copy whoever deploys |
| Deployed by | you, `make deploy` | GitHub Actions on push to `main` |
| Dashboard file | `src/dashboards/neobank_analytics.lvdash.json` | rendered copy with `neobank_prod` names |
| ABAC policies | `enable_abac_policies` in `envs/dev/terraform.tfvars` | same flag in `envs/prod/terraform.tfvars` |
| `sample_rows` | 500k | 500k (override in the prod target for the full dataset) |

**Shared by both:** the SQL warehouse, the Slack and email destinations (prod
alerts go to the same channel), the groups and the governed tag keys.

### Who runs what, and who owns what

Terraform runs as **you**, and prod bundle deploys and runs as **`sp-github-cicd`**.
That split is deliberate: the SP can create and change data, but it can't grant
itself access or change governance.

| Object (prod) | Created by | Owner | What the other identity needs |
|---|---|---|---|
| Catalog, schemas, volume, grants, ABAC policies | Terraform | you | SP: catalog privileges (`modules/neobank_env`, `bundle_privileges`) |
| Governed tag keys | Terraform (`shared`) | you (tag manager) | SP: **ASSIGN** on each tag, to run `tag_gold_columns` (`databricks_access_control_rule_set.governed_tag`) |
| Tables, UDFs, metric views | bundle (pipeline, jobs) | SP | you: nothing extra; you own the catalog and schemas above them |
| Jobs, pipeline, dashboard | bundle | SP | you: `CAN_MANAGE` from the prod target's `permissions` |

Two rules follow from it:

- **Deploy prod from CI only.** A local `make deploy TARGET_ENV=prod` would deploy
  as you into the SP's `root_path`, mixing file ownership in one deployment.
- **Run Terraform as one identity.** The tag rule sets keep the current
  Terraform user as manager, so a different runner would take that role over. To
  remove the dependency on a personal account later, run Terraform as its own
  service principal and set catalog ownership to a group.

---

## 5. First-time setup of an environment

Each step depends on the previous one. The bundle needs the schemas, the ABAC
policies need the UDFs, and tagging needs the tables. So Terraform runs before
the bundle, and once more for the policies. The reasoning is in
[DATA_GOVERNANCE.md §5](DATA_GOVERNANCE.md#5-cross-tool-sequencing-chicken-and-egg).

```bash
# TARGET_ENV=<env> in .env, then: direnv allow

# 0. Once per workspace: groups in the UI (WORKSPACE_SETUP.md §4), then
#    identities, destinations, tag keys and tag permissions
make tf-shared-apply

# 1. Create the catalog with SQL. Free Edition can't create catalogs through the
#    API; the import block in terraform/envs/<env>/main.tf adopts it, and plan
#    fails until it exists (details: WORKSPACE_SETUP.md §2).
#    CREATE CATALOG IF NOT EXISTS neobank_<env>;       -- in the SQL editor

# 2. Schemas, volume, grants (ABAC policies skipped)
make tf-apply

# 3. Jobs, pipeline, dashboard + the mask / row-filter UDFs
make deploy                      # prod: push to main and let CI deploy
databricks bundle run neobank_security_functions

# 4. ABAC policies: set enable_abac_policies = true in
#    terraform/envs/<env>/terraform.tfvars
make tf-apply

# 5. Build the tables; tag_gold_columns tags them and the policies apply at once
databricks bundle run neobank_daily       # uses compute
```

Steps 0–2 and 4 are one-time per workspace or environment.

---

## 6. Day to day: what to change where

| Change | Edit | Then |
|---|---|---|
| Pipeline logic, new column | `src/pipelines/` | `make deploy` in dev, test, merge → CI deploys prod |
| New sensitive column | one line in `src/governance/tag_gold_columns.sql` | same; the existing policy masks it straight away |
| Mask / filter logic | `src/udf/` | deploy, then rerun `neobank_security_functions` in each env |
| New KPI | `src/metrics/create_metric_views.py` | deploy, rerun `neobank_daily` (or its `build_metrics_views` task) |
| Dashboard | edit in the dev workspace → `databricks bundle generate dashboard --resource neobank_analytics --force` → commit | CI renders the prod copy and deploys |
| New schema, grant or policy | `terraform/modules/neobank_env/main.tf` | `make tf-apply` with `TARGET_ENV=dev`, then `prod` |
| New SP, destination or tag key | `terraform/shared/` | `make tf-shared-apply` once |

The UDFs use `CREATE OR REPLACE`, so reruns are safe. Never drop or rename a UDF
while a policy references it: remove the policy in Terraform first.

---

## 7. CI/CD

`.github/workflows/bundle-deploy.yml` deploys the **bundle only**. Terraform
stays on your machine (§9).

| Job | Runs on | What |
|---|---|---|
| `validate-dev` | every PR and every push to `main` | `make validate` with `TARGET_ENV=dev` and the `dev` GitHub environment |
| `deploy-prod` | push to `main` or a manual run on `main`, after `validate-dev` passes, and only if `PROD_DEPLOY_ENABLED=true` | `make validate` then `make deploy` with `TARGET_ENV=prod`, as `sp-github-cicd`; one deploy at a time |

So a PR only validates, and merging to `main` deploys prod. To redeploy without a
commit, use Actions → `bundle-deploy` → *Run workflow* on `main`.

Both jobs authenticate as `sp-github-cicd` with only `DATABRICKS_CLIENT_ID` and
`DATABRICKS_CLIENT_SECRET`. The host comes from `databricks.yaml`, and the target
from `TARGET_ENV` in each job, so CI and your machine run identical `make` commands.

On a public repo, PRs from **forks** get no secrets, so `validate-dev` fails for
them. That's expected; don't switch to `pull_request_target` to work around it,
since that would hand the SP secret to untrusted code.

### GitHub setup (Terraform)

GitHub is configured by `terraform/shared/github.tf`, next to the SP whose secret
it publishes. Nothing is copied by hand.

| Resource | Creates |
|---|---|
| `github_repository_environment.this` | environments `dev` and `prod`; `prod` deployable from `main` only, plus required reviewers if `prod_reviewers` is set |
| `github_repository_environment_deployment_policy.prod_main` | the `main` branch rule for `prod` |
| `github_actions_environment_secret.databricks` | `DATABRICKS_CLIENT_ID` / `DATABRICKS_CLIENT_SECRET` in both environments |
| `github_actions_variable.prod_deploy_enabled` | **repository** variable `PROD_DEPLOY_ENABLED`. Repository level because the job's `if:` runs before the environment loads, so an environment variable would read as empty |

Environment protection rules (reviewers, branch rules) are free on public
repositories. On a private repo they need a paid plan.

**Setup, once:**

1. **Apply prod Terraform first** (§5, steps 0–2). The SP, its grants on
   `neobank_prod` and the notification destinations must exist before CI can deploy.
2. **Create a fine-grained token:** GitHub → Settings → Developer settings →
   Fine-grained tokens. Limit it to *Only select repositories* → `neobank_lakehouse`.
   Repository permissions: **Administration**, **Environments**, **Secrets** and
   **Variables**: read and write (Metadata: read is added automatically).
3. **Add it to `.env`** (gitignored; direnv exports it): `GITHUB_TOKEN=github_pat_...`
4. **Optional, require approval for prod deploys:** in `terraform/shared/terraform.tfvars`,
   set `prod_reviewers = ["<your-github-username>"]`. GitHub lets you approve your own
   deploys, so this works for a solo repo.
5. **Apply:** `make tf-shared-apply`.

Terraform is the only creator of these settings; don't add or edit them in the
UI. An entry created there makes the apply fail with `409 Already exists`
(fix in §10).

**Day to day:**

| Want to… | Do |
|---|---|
| pause prod deploys | `prod_deploy_enabled = false` in `terraform.tfvars`, `make tf-shared-apply` |
| add or remove a prod approver | edit `prod_reviewers`, `make tf-shared-apply` |
| check nobody changed GitHub by hand | `make tf-shared-plan` shows drift in environments, branch rules and the variable. Secret values can't be read back from GitHub; `make tf-shared-apply` rewrites them from Terraform |

**After the first CI deploy**, finish the environment by hand: UDFs, then ABAC
policies, then the first run (§5, steps 3–5, with `-t prod` / `TARGET_ENV=prod`).

### Rotating the CI/CD secret

```bash
terraform -chdir=terraform/shared apply -replace=databricks_service_principal_secret.sp_cicd_secret
```

The same apply creates the new secret and writes it to both GitHub environments,
so CI keeps working. Revoke the token in `.env` if it leaks; it can change
environments and secrets of this repo.

### Dashboard per environment

A metric-view dataset needs a fully qualified `asset_name`, and
`dataset_catalog` / `dataset_schema` don't apply to it. So
`src/dashboards/neobank_analytics.lvdash.json` is the dev copy you edit, and
`make dashboards TARGET_ENV=prod` renders
`build/dashboards/neobank_analytics.prod.lvdash.json` with `neobank_prod` names.
That copy is gitignored, and the prod target reads it (`databricks.yaml`).
`make validate` and `make deploy` render it first, so you only hit a missing file
when calling `databricks bundle ... -t prod` directly.

---

## 8. Adding an environment (e.g. `staging`)

1. Add `"staging"` to the `env` validation in `terraform/modules/neobank_env/variables.tf`.
2. Copy `terraform/envs/dev` to `terraform/envs/staging` and set `env = "staging"`
   in `main.tf`.
3. Add a `staging` target to `databricks.yaml` (catalog `neobank_staging`, mode,
   `run_as`), plus a dashboard `file_path` override if it isn't dev.
4. Add a GitHub environment and job if CI should deploy it.
5. Run §5 with `TARGET_ENV=staging`.

Modules and `terraform/shared` stay as they are.

---

## 9. Limits

- **Terraform runs from your machine only.** State is local and holds SP secrets,
  so CI can't plan or apply. To automate it, move each root to a remote backend
  with its own key (commented example in each `versions.tf`).
- **Dev and prod share a workspace and a metastore.** Workspace admins see both,
  and a grant on `neobank_prod` works from anywhere attached to the metastore.
  For a hard boundary, use a separate prod workspace with workspace-catalog binding
  ([PERMISSIONS_REFERENCE.md §7.6](PERMISSIONS_REFERENCE.md#76-workspace-catalog-binding)).
  `terraform/shared` then becomes one root per workspace.
- **Group membership is manual** on Free Edition (see
  [WORKSPACE_SETUP.md §4](WORKSPACE_SETUP.md#4-how-this-repo-handles-it)).

---

## 10. Troubleshooting

| Symptom | Fix |
|---|---|
| `land_data`: `/Volumes/neobank_<env>/bronze/raw not found` | Terraform hasn't been applied for this env: `make tf-apply`. |
| `terraform plan`: `Cannot import non-existent remote object` | Create the catalog first: `CREATE CATALOG IF NOT EXISTS neobank_<env>;` |
| `lookup` fails for `slack_neobank` / `sp-github-cicd` | Apply the shared layer: `make tf-shared-apply`. |
| `bundle validate -t prod`: dashboard file not found | Use `make validate TARGET_ENV=prod`, which renders it first. |
| Prod resources point at `neobank_dev` | `BUNDLE_VAR_catalog` is exported in your shell; unset it (§3). |
| ABAC policy create fails: function not found | Run `neobank_security_functions` in that env before `enable_abac_policies = true`. |
| `deploy-prod` shows as skipped | `validate-dev` failed, `PROD_DEPLOY_ENABLED` isn't `true` (`make tf-shared-plan` shows it), or the run wasn't on `main` (§7). |
| `deploy-prod` waits: "Waiting for review" | `prod_reviewers` is set: approve it in the run's page. |
| CI: `invalid client secret` / auth error | The GitHub secret is out of date (edited by hand?): `make tf-shared-apply` writes it again. |
| `make tf-shared-apply`: GitHub `401` / `403` | `GITHUB_TOKEN` missing from `.env`, expired, or lacking a permission from §7 step 2. |
| `make tf-shared-apply`: GitHub `409 Already exists` | The object was created in the UI. Delete it there and apply again (§7). |
| Prod `tag_gold_columns` fails: no permission to assign tag | The SP lacks ASSIGN on the governed tag: `make tf-shared-apply` (rule sets in `governed_tags.tf`). |
| A grant you added by hand disappeared | `databricks_grants` is authoritative; add it in `modules/neobank_env`. |

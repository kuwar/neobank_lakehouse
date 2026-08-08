# Databricks Asset Bundles — The Complete, Corrected Tutorial (Free Edition, 2026)

> **This supersedes my earlier notes.** The one correction that matters most:
> **notebooks and `.py` files are NOT "artifacts."** Artifacts means *built* things only
> (wheels, JARs). Source code lives in `src/` and is *synced*, not built. That single
> mix-up is what made the concept feel murky — it's fixed throughout this document.

---

## 0. Read this first: can a mistake cost me money?

**No — not on Free Edition.** The Databricks Free Edition (which replaced the old Community
Edition on Jan 1, 2026) is **free forever**. There is no credit card and no bill.

What a mistake *can* cost you is your **daily compute quota**. Free Edition runs on serverless
compute under a fair-usage policy: if you burn through the quota, your compute is paused for the
rest of the day (rarely, the rest of the month). Your data and settings are never deleted — you
just wait for the reset.

So "expensive mistake" here means **wasting quota on a bad run**, or worse, **learning a habit
that would cost real money on a paid workspace later**. Everything in this tutorial is built
around a workflow that stays safe in both worlds:

```
  validate  →  plan  →  deploy -t dev  →  run  →  destroy
   (free)     (free)      (free)      (COMPUTE)   (free)
```

Only `run` spends compute. `validate`, `plan`, `deploy`, `summary`, and `destroy` do not.
Get in the habit of validating and planning *every* time before you deploy, and always working
in a `dev` target first. That habit is your entire cost-safety strategy.

---

## 1. Naming: "Asset Bundles" vs "Declarative Automation Bundles"

In March 2026 Databricks **renamed** *Databricks Asset Bundles* to *Declarative Automation
Bundles*. Nothing about how you use them changed:

- the config file is still `databricks.yml`
- the CLI command group is still `databricks bundle ...`
- everyone still says "DABs"

If a doc, blog post, or tutorial says either name, it's the same thing. Don't let the two names
confuse you.

---

## 2. The mental model: four blocks, each answers ONE question

A bundle is a project folder described as code. It has four YAML blocks plus your source files.
Here is the whole thing at a glance:

```
  Bundle project folder (in Git)
  ┌───────────────────────────────────────────────┐
  │  databricks.yml                                │
  │  ┌──────────────────────────────────────────┐ │
  │  │ bundle:     the project's identity (name) │ │
  │  │ artifacts:  BUILD wheels/JARs  (optional) │ │        deploy
  │  │ resources:  the OBJECTS to create  ◄──────┼─┼───────────────►  Databricks
  │  │ targets:    WHERE to deploy (dev / prod)  │ │                  workspace
  │  └──────────────────────────────────────────┘ │              (resources run here)
  │  src/   notebooks & .py  —  SYNCED, not built  │
  └───────────────────────────────────────────────┘
```

| Block (YAML key) | The one question it answers | What goes in it |
|---|---|---|
| `bundle:` | *What is this project called?* | Just the name (part of the bundle's identity). |
| `artifacts:` | *What needs to be **built**?* | Python wheels, JARs. **Optional** — skip it if you have no custom package. |
| `resources:` | *What Databricks **objects** am I deploying?* | jobs, pipelines, apps, dashboards, models, schemas, volumes… |
| `targets:` | *****Where** and in what **mode**?* | dev/prod workspaces + per-environment overrides. |
| `src/` (not a block) | *What **code** runs?* | notebooks and `.py` files — just sit in the folder, referenced by resources. |

**How they connect:** artifacts get *built* and source files get *synced*; `resources` point at
both (a task references `notebook_path: ./src/x.py` or a built `whl`); `targets` decide which
workspace it all lands in and with what overrides.

---

## 3. Free Edition constraints (memorize these)

| Constraint | What it means for your bundle |
|---|---|
| **Serverless only** | No classic clusters. Never write `new_cluster` / `job_clusters` with node types — they will fail. |
| **Say "yes" to serverless** | The `default-python` template asks; answer yes. For pipelines, set `serverless: true`. |
| **Deploy from your laptop** | Deploying *inside* the serverless workspace can fail (the old Terraform engine tries to reach `releases.hashicorp.com`, which is blocked). Deploy from your **local CLI**. |
| **Direct engine avoids Terraform** | Newer CLI versions offer a Terraform-free engine. Run `databricks bundle deployment migrate` to switch a bundle to it. |
| **Wheels install differently** | On serverless, prefer `%pip install` in the notebook or an `environments` spec over classic cluster libraries. |
| **Limited outbound internet** | Only a small set of trusted domains is reachable from compute. |

---

## 4. Install and authenticate the CLI

```bash
# Install (pick your platform)
brew install databricks                                   # macOS / Linux (Homebrew)
winget install Databricks.DatabricksCLI                   # Windows
curl -fsSL https://raw.githubusercontent.com/databricks/setup-cli/main/install.sh | sh

# Verify — you want v0.218.0 or higher (v1.x is current in 2026)
databricks --version
```

Authenticate to your Free Edition workspace:

1. In the workspace UI: **Settings → Developer → Access tokens → Manage → Generate new token**. Copy it.
2. Configure a profile:

```bash
databricks configure
#   Databricks host: https://<your-workspace>.cloud.databricks.com   (copy from browser, no trailing slash)
#   Personal Access Token: <paste>
```

3. Test it:

```bash
databricks current-user me
```

---

## 5. Full command reference (with examples)

Every command is `databricks bundle <command>`. Add `-h` to any command to see its flags.

### `init` — start a new bundle from a template

```bash
databricks bundle init                    # interactive template picker
databricks bundle init default-python     # standard Python template by name
databricks bundle init https://github.com/org/template   # custom template from Git
```

The Python template asks **"Use serverless?"** → answer **yes** on Free Edition.

### `validate` — check the config is correct *(no compute)*

```bash
databricks bundle validate            # default target
databricks bundle validate -t prod    # a specific target
```

Prints the bundle identity and `Validation OK!`, and warns about unknown properties. Run it constantly.

### `plan` — preview what a deploy will do *(no compute)*

```bash
databricks bundle plan
# create jobs.my_bundle_job
# create pipelines.my_bundle_pipeline
```

The "terraform plan" of DABs: shows create/update/delete actions **without changing anything**.
Use `--select my_job` to scope it to one resource.

### `deploy` — push artifacts + resources to the workspace *(no compute run)*

```bash
databricks bundle deploy -t dev
databricks bundle deploy -t prod
```

Re-deploy behavior: in-config-but-not-in-workspace → **created**; in both → **updated**;
removed-from-config → **deleted**. Useful flags:

- `--auto-approve` — skip prompts (CI).
- `--fail-on-active-runs` — abort if something is currently running.
- `--force-lock` — reclaim a stale lock after a crash.
- `--select my_job` — **dev only**, deploy one resource + upstreams (not for prod).

### `run` — run a job, pipeline, app, or script *(THIS uses compute)*

```bash
databricks bundle run hello_job                 # run a job
databricks bundle run -t dev hello_job          # in a target
databricks bundle run                           # no key → picker
```

Pass parameters (recommended way):

```bash
databricks bundle run --params run_date=2026-08-07,region=eu hello_job
```

Run only some tasks (dependency modifiers: `+` prefix = upstreams, suffix `+` = downstreams):

```bash
databricks bundle run --only ingest,transform hello_job
databricks bundle run --only +transform+ hello_job
```

Pipelines:

```bash
databricks bundle run my_pipeline --validate-only     # graph check, no materialization
databricks bundle run my_pipeline --full-refresh-all
```

Apps must be re-run after each deploy to pick up new code:

```bash
databricks bundle deploy -t prod && databricks bundle run my_app -t prod
```

Other flags: `--no-wait` (return immediately), `--restart` (cancel + rerun a live run).

### `summary` — deployed identity + clickable links *(no compute)*

```bash
databricks bundle summary
databricks bundle summary --force-pull   # ignore local cache, read state from workspace
```

### `open` — jump to a resource in the browser *(no compute)*

```bash
databricks bundle open                     # picker
databricks bundle open my_pipeline
```

### `generate` — reverse-engineer YAML from existing workspace resources

Supported: `job`, `pipeline`, `dashboard`, `app`, `genie-space`.

```bash
databricks bundle generate job --existing-job-id 123456789 --bind
databricks bundle generate pipeline --existing-pipeline-id abc-123-def
```

> **Without `--bind`, deploying the generated config creates a NEW resource instead of updating
> the existing one.** Always `--bind` (or run `bundle deployment bind`) when adopting something
> you built in the UI. Job generate currently supports notebook-task jobs only.

### `deployment` — bind / unbind / migrate

```bash
databricks bundle deployment bind hello_job 123456789 -t dev     # attach to existing job
databricks bundle deployment unbind hello_job
databricks bundle deployment migrate                             # move off Terraform (direct engine)
```

Bind ID formats: job = numeric ID, pipeline = UUID, Unity Catalog objects = full
`catalog.schema[.object]` name.

### `sync` — one-way file sync (local → workspace) *(no compute)*

```bash
databricks bundle sync --dry-run
databricks bundle sync --watch     # continuous sync while you edit
```

### `schema` — dump the JSON schema of `databricks.yml`

```bash
databricks bundle schema > bundle_config_schema.json   # point your IDE at this for autocomplete
```

### `destroy` — delete everything the bundle deployed *(no compute)*

```bash
databricks bundle destroy -t dev                 # prompts to confirm
databricks bundle destroy -t dev --auto-approve
```

⚠️ **Permanent.** Deletes the bundle's deployed jobs, pipelines, and artifacts. Protect specific
resources with a `lifecycle` setting if you don't want them destroyable.

### Global flags (any command)

| Flag | Purpose |
|---|---|
| `-t, --target <name>` | Which target to act on |
| `-p, --profile <name>` | Auth profile from `~/.databrickscfg` |
| `--var "foo=bar"` | Override a bundle variable at runtime |
| `-o, --output text\|json` | Output format |
| `--debug` | Verbose logging |
| `-h, --help` | Help for any command |

---

## 6. Anatomy of a real `databricks.yml` (fully annotated)

```yaml
# BLOCK 1 — identity
bundle:
  name: sales_project

# Pull in resource files kept in a resources/ folder (keeps databricks.yml small)
include:
  - resources/*.yml

# Reusable values, overridable per target
variables:
  catalog:
    description: Catalog to write to
    default: main

# BLOCK 2 — artifacts: ONLY things that must be built. Omit entirely if none.
# artifacts:
#   my_lib:
#     type: whl
#     build: python -m build --wheel
#     path: ./my_lib

# BLOCK 3 — resources: the Databricks objects to create
resources:
  jobs:
    daily_sales_job:
      name: daily_sales_job
      parameters:
        - name: run_date
          default: "2026-08-01"
      tasks:
        - task_key: ingest
          notebook_task:
            notebook_path: ../src/ingest.py     # references a SOURCE file (synced)
      # No cluster block => serverless (required on Free Edition)

# BLOCK 4 — targets: environments, each can override the blocks above
targets:
  dev:
    mode: development        # prefixes names "[dev you]", pauses schedules — SAFE sandbox
    default: true
    variables:
      catalog: main
    workspace:
      host: https://<your-workspace>.cloud.databricks.com
  prod:
    mode: production         # strict validation, no name prefixing
    variables:
      catalog: main
    workspace:
      host: https://<your-workspace>.cloud.databricks.com
```

`mode: development` vs `mode: production` is your built-in safety switch. Dev prefixes every
resource with `[dev your_name]`, pauses schedules and triggers, and tags runs as dev — so you can
iterate without ever touching a production object.

---

## 7. Tutorials (hands-on, Free Edition, run locally)

Each builds on the last. Run everything from your **local terminal**.

### Tutorial 1 — Your first bundle end to end

```bash
databricks bundle init default-python
#   Project name: my_first_bundle
#   Include a notebook? yes
#   Include a pipeline? no
#   Include a Python package? no
#   Use serverless? YES        <-- required

cd my_first_bundle

databricks bundle validate      # "Validation OK!"  (free)
databricks bundle plan          # preview: create jobs.<name>  (free)
databricks bundle deploy -t dev # upload to dev  (free)
databricks bundle summary       # grab the deep link
databricks bundle run -t dev <job_key>   # the ONE step that uses compute
databricks bundle destroy -t dev         # clean up  (free)
```

Your job shows up under **Jobs & Pipelines** as `[dev your_name] ...`, and files land under
`/Workspace/Users/you@x.com/.bundle/my_first_bundle/dev/files`.

### Tutorial 2 — A serverless job from scratch

`resources/etl_job.yml`:

```yaml
resources:
  jobs:
    etl_job:
      name: etl_job
      parameters:
        - name: run_date
          default: "2026-08-01"
      tasks:
        - task_key: ingest
          notebook_task:
            notebook_path: ../src/ingest.py
        - task_key: transform
          depends_on:
            - task_key: ingest
          notebook_task:
            notebook_path: ../src/transform.py
      # No cluster => serverless
```

`src/ingest.py`:

```python
# Databricks notebook source
dbutils.widgets.text("run_date", "")
run_date = dbutils.widgets.get("run_date")
print(f"Ingesting for {run_date}")
```

```bash
databricks bundle validate
databricks bundle deploy -t dev
databricks bundle run --params run_date=2026-08-07 etl_job -t dev
databricks bundle run --only transform etl_job -t dev   # run just one task
```

### Tutorial 3 — A serverless Lakeflow pipeline

`resources/sample_pipeline.yml`:

```yaml
resources:
  pipelines:
    sample_pipeline:
      name: sample_pipeline
      serverless: true          # required on Free Edition
      catalog: main
      schema: default
      libraries:
        - notebook:
            path: ../src/pipeline.py

  jobs:
    run_pipeline_job:
      name: run_pipeline_job
      tasks:
        - task_key: refresh
          pipeline_task:
            pipeline_id: ${resources.pipelines.sample_pipeline.id}   # substitution, resolved at deploy
```

`src/pipeline.py`:

```python
import dlt

@dlt.table
def sample_table():
    return spark.range(10).withColumnRenamed("id", "n")
```

```bash
databricks bundle deploy -t dev
databricks bundle run sample_pipeline --validate-only -t dev   # graph check first (cheap)
databricks bundle run sample_pipeline -t dev                   # real run
```

### Tutorial 4 — Variables and multiple environments

```yaml
variables:
  catalog:
    default: main
  notifications_email:
    default: ""

resources:
  jobs:
    etl_job:
      name: etl_job-${var.catalog}
      email_notifications:
        on_failure:
          - ${var.notifications_email}
      tasks:
        - task_key: main
          notebook_task:
            notebook_path: ../src/main.py

targets:
  dev:
    mode: development
    default: true
    variables:
      catalog: sandbox
  prod:
    mode: production
    variables:
      catalog: main
      notifications_email: alerts@example.com
```

```bash
databricks bundle deploy -t dev
databricks bundle deploy -t prod
databricks bundle deploy -t dev --var "catalog=scratch"   # ad-hoc override
```

### Tutorial 5 — Adopt a job you built in the UI

```bash
# Job ID comes from the job page URL in the workspace
databricks bundle generate job --existing-job-id 123456789 --bind
```

This writes `resources/<job>.yml`, downloads the referenced notebooks into `src/`, and (because of
`--bind`) links the config to the real job so your next `deploy` **updates** it instead of cloning
it. Commit to Git — you're now managing it as code.

### Tutorial 6 (optional) — Build and use a Python wheel

Only needed when you have reusable Python code to share across tasks.

Project addition:

```
my_lib/
├── pyproject.toml
└── src/my_lib/__init__.py
```

`my_lib/pyproject.toml`:

```toml
[build-system]
requires = ["setuptools>=61.0", "wheel"]
build-backend = "setuptools.build_meta"

[project]
name = "my_lib"
version = "0.1.0"
```

In `databricks.yml`:

```yaml
artifacts:
  my_lib:
    type: whl
    build: python -m build --wheel   # runs locally during deploy
    path: ./my_lib

resources:
  jobs:
    wheel_job:
      name: wheel_job
      tasks:
        - task_key: main
          python_wheel_task:
            package_name: my_lib
            entry_point: main
          libraries:
            - whl: ./my_lib/dist/*.whl
```

On `deploy`, the CLI runs the build command, produces the `.whl`, uploads it, and installs it on
the task. On Free Edition serverless, if the classic library install is awkward, fall back to
`%pip install` inside a notebook instead.

---

## 8. Safety checklist — avoid wasting quota (and money later)

```
BEFORE every deploy:
  [ ] databricks bundle validate        # catches typos for free
  [ ] databricks bundle plan            # confirm create/update/delete is what you expect

ALWAYS:
  [ ] work in a `dev` target (mode: development) first
  [ ] deploy from your LOCAL machine, not inside the serverless workspace
  [ ] test with a small run before any full-refresh or large job

BEFORE run (the only compute step):
  [ ] use --validate-only on pipelines to check the graph cheaply
  [ ] pass small/sample parameters first

WHEN DONE experimenting:
  [ ] databricks bundle destroy -t dev  # remove leftover jobs/pipelines so nothing lingers
```

Why this matters even though Free Edition is free: these are the exact habits that keep a *paid*
workspace from running up a bill. Learning them now means you never learn the expensive way.

---

## 9. Troubleshooting

| Symptom | Cause / Fix |
|---|---|
| `error downloading Terraform ... releases.hashicorp.com` | Deploying inside serverless. Deploy from your local machine, or run `databricks bundle deployment migrate`. |
| Auth fails in CLI / VS Code | Regenerate PAT (**Settings → Developer**), re-run `databricks configure`, ensure host has no trailing slash, then `databricks current-user me`. |
| `Cluster not found` / node type errors | You defined a classic cluster. Remove it; use serverless (`serverless: true` for pipelines). |
| Wheel/library install fails on serverless | Use `%pip install` in the notebook or an `environments` spec. |
| Deploy created a duplicate instead of updating | Resource wasn't bound. Use `generate --bind` or `bundle deployment bind`. |
| Compute suddenly unavailable | You hit the Free Edition daily quota. Wait for reset; data is safe. |
| Names show as `[dev yourname] ...` | Expected in `mode: development`. Use a `prod` target to drop the prefix. |

---

## 10. One-page cheat sheet

```bash
# Setup
databricks --version
databricks configure && databricks current-user me

# Safe loop (repeat validate → plan → deploy → run)
databricks bundle init default-python      # say YES to serverless
databricks bundle validate                 # free
databricks bundle plan                     # free
databricks bundle deploy -t dev            # free
databricks bundle run <key> -t dev         # USES COMPUTE
databricks bundle summary                  # free — links
databricks bundle destroy -t dev           # free — cleanup

# Parameters & scoping
databricks bundle run --params k=v <job>
databricks bundle run --only +task+ <job>
databricks bundle run <pipeline> --validate-only

# Adopt existing resources
databricks bundle generate job --existing-job-id <id> --bind
databricks bundle deployment bind <key> <id> -t dev

# Free Edition fix
databricks bundle deployment migrate       # Terraform-free engine
```

---

### Official references
- What are Declarative Automation Bundles: `https://docs.databricks.com/aws/en/dev-tools/bundles/`
- `bundle` command group: `https://docs.databricks.com/aws/en/dev-tools/cli/bundle-commands`
- Configuration reference: `https://docs.databricks.com/aws/en/dev-tools/bundles/reference`
- Resources reference: `https://docs.databricks.com/aws/en/dev-tools/bundles/resources`
- Free Edition limitations: `https://docs.databricks.com/aws/en/getting-started/free-edition-limitations`
- Build a Python wheel with bundles: `https://docs.databricks.com/aws/en/dev-tools/bundles/python-wheel`

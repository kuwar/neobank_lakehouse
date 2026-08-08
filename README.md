# <project-name>

<One-line description of what this bundle deploys — e.g. "Daily sales ingestion and
transformation jobs, deployed as a Databricks Asset Bundle.">

This repository is a **Databricks Asset Bundle** (DAB). All jobs, pipelines, and their
source code are defined as code in `databricks.yml` and deployed with the Databricks CLI.
The repository is the single source of truth — do not edit deployed files directly in the
workspace.

> **New to this project?** Jump to [Quick start](#quick-start). New to bundles? See the
> [workflow](#development-workflow) and [how files are deployed](#where-files-are-deployed).

---

## Prerequisites

- **Databricks CLI** v0.218.0 or newer (v1.x recommended). Check with `databricks --version`.
- Access to the target Databricks workspace(s).
- Python 3.x (only if this bundle builds a wheel — see [Building the library](#building-the-library)).
- A personal access token or OAuth login for authentication.

Install the CLI:

```bash
# macOS / Linux
brew install databricks
# Windows
winget install Databricks.DatabricksCLI
# Universal script
curl -fsSL https://raw.githubusercontent.com/databricks/setup-cli/main/install.sh | sh
```

---

## Quick start

```bash
# 1. Authenticate (once per machine)
databricks configure           # host: https://<workspace>.cloud.databricks.com  + token

# 2. Verify auth
databricks current-user me

# 3. Validate and preview before deploying (neither uses compute)
databricks bundle validate -t dev
databricks bundle plan -t dev

# 4. Deploy to your dev environment
databricks bundle deploy -t dev

# 5. Run a resource (this is the only step that consumes compute)
databricks bundle run <resource_key> -t dev

# 6. Tear down when finished experimenting
databricks bundle destroy -t dev
```

---

## Authentication

1. In the workspace UI: **Settings → Developer → Access tokens → Manage → Generate new token**.
2. Run `databricks configure` and paste the workspace host (no trailing slash) and token.

This writes a profile to `~/.databrickscfg`. To use a named profile, pass `-p <profile>` on any
command. Prefer OAuth? Use `databricks auth login --host https://<workspace>.cloud.databricks.com`.

> Deploy from your **local machine**, not from inside the workspace. See
> [Free Edition notes](#free-edition--serverless-notes).

---

## Project structure

```
.
├── databricks.yml          # Bundle definition: name, variables, targets, includes
├── resources/              # Resource definitions, one file per job/pipeline
│   ├── <job>.yml
│   └── <pipeline>.yml
├── src/                    # Source code — notebooks and .py files (synced, not built)
│   ├── ingest.py
│   └── transform.py
├── <my_lib>/               # (optional) Python package built into a wheel
│   ├── pyproject.toml
│   └── src/<my_lib>/
└── README.md
```

What each part is for:

| Path / block | Purpose |
|---|---|
| `databricks.yml` → `bundle:` | The project's identity (its name). |
| `databricks.yml` → `variables:` | Reusable values, overridable per target. |
| `databricks.yml` → `targets:` | Deployment environments (`dev`, `prod`) and their overrides. |
| `resources/*.yml` → `resources:` | The Databricks objects to create (jobs, pipelines, apps). |
| `src/` | Notebooks and Python files. Referenced by resources; synced on deploy. |
| `<my_lib>/` | Optional built library; declared under `artifacts:` and attached to a task. |

---

## Configuration

Environments are defined under `targets:` in `databricks.yml`. This project uses:

| Target | Mode | Purpose |
|---|---|---|
| `dev` | `development` | Personal sandbox. Resource names are prefixed `[dev <you>]`; schedules paused. |
| `prod` | `production` | Shared production. Strict validation; no name prefixing. |

Common variables (override per target or with `--var "name=value"`):

| Variable | Default | Description |
|---|---|---|
| `catalog` | `<main>` | Unity Catalog catalog to write to. |
| `<other>` | `<...>` | `<describe>` |

Override examples:

```bash
databricks bundle deploy -t dev --var "catalog=sandbox"
databricks bundle deploy -t prod
```

---

## Development workflow

Always follow this order. Only `run` consumes compute; everything else is free to run as often
as you like, so validate and plan before every deploy.

```
validate  →  plan  →  deploy -t dev  →  run  →  destroy
 (free)      (free)      (free)      (compute)   (free)
```

1. **Edit locally.** Change notebooks/`.py` in `src/` and resource YAML in `resources/`.
2. **Validate.** `databricks bundle validate -t dev` — catches config errors for free.
3. **Plan.** `databricks bundle plan -t dev` — preview create/update/delete actions.
4. **Deploy.** `databricks bundle deploy -t dev` — syncs files and applies resources.
5. **Run.** `databricks bundle run <key> -t dev` — executes; pass params with `--params k=v`.
6. **Inspect.** `databricks bundle summary` for links, or `databricks bundle open <key>`.
7. **Clean up.** `databricks bundle destroy -t dev` removes everything this bundle deployed.

For a fast inner loop, run `databricks bundle sync --watch` in a separate terminal to push file
edits continuously without a full deploy.

---

## Where files are deployed

On deploy, the CLI **incrementally** syncs your files into a per-target folder in the workspace:

```
/Workspace/Users/<you>/.bundle/<project-name>/<target>/
├── files/       # your src/ tree, preserved exactly (e.g. files/src/ingest.py)
├── artifacts/   # built wheels/JARs (under .internal/)
└── state/       # deployment metadata — do not edit
```

`dev` and `prod` deploy to **separate folders**, so dev work never touches prod. A task written
as `notebook_path: ./src/ingest.py` resolves to `.../<target>/files/src/ingest.py` after deploy.

> **Source of truth is this repo.** Deploy only uploads files that changed *locally*. Editing a
> notebook directly in the workspace will not be overwritten by the next deploy and causes drift —
> always edit locally and redeploy. Override the base path with `workspace.root_path` if needed.

---

## Building the library

*(Delete this section if the bundle has no `artifacts:` block.)*

Reusable Python code lives in `<my_lib>/` and is built into a wheel at deploy time:

```yaml
artifacts:
  <my_lib>:
    type: whl
    build: python -m build --wheel
    path: ./<my_lib>
```

Prerequisites: `pip install build wheel setuptools`. The wheel is built locally on `deploy`,
uploaded to `artifacts/`, and attached to the task's `libraries`. On serverless compute, prefer
`%pip install` or an `environments` spec if a classic library install fails.

---

## Command reference

| Command | What it does | Uses compute? |
|---|---|---|
| `databricks bundle validate -t <t>` | Check config syntax | No |
| `databricks bundle plan -t <t>` | Preview changes | No |
| `databricks bundle deploy -t <t>` | Sync files + apply resources | No |
| `databricks bundle run <key> -t <t>` | Execute a job/pipeline | **Yes** |
| `databricks bundle summary` | Show deployed identity + links | No |
| `databricks bundle open <key>` | Open a resource in the browser | No |
| `databricks bundle sync --watch` | Continuously sync file edits | No |
| `databricks bundle generate job --existing-job-id <id> --bind` | Adopt a UI-built job | No |
| `databricks bundle destroy -t <t>` | Delete deployed resources | No |

Add `-h` to any command for its full flags.

---

## Free Edition / serverless notes

*(Remove this section if the target workspaces are paid tiers.)*

- **Serverless only** — no classic clusters. Do not add `new_cluster`/`job_clusters` blocks; set
  `serverless: true` on pipelines.
- **Deploy from your local machine** — deploying inside the serverless workspace can fail on a
  blocked Terraform download. If it does, run `databricks bundle deployment migrate` to switch to
  the Terraform-free engine.
- **Fair-usage quota** — Free Edition is free with no bill, but exceeding the daily compute quota
  pauses compute until reset. Data and settings are never deleted. Test with small runs first.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `error downloading Terraform … hashicorp.com` | Deploy locally, or run `databricks bundle deployment migrate`. |
| Auth failures | Regenerate the token, re-run `databricks configure`, confirm host has no trailing slash. |
| `Cluster not found` / node type errors | Remove classic cluster config; use serverless. |
| Deploy created a duplicate instead of updating | Bind it: `databricks bundle deployment bind <key> <id> -t <t>`. |
| Files not appearing in the workspace | Confirm they're under the bundle root or a `sync.paths` entry; check `.gitignore`. |
| Workspace edits keep reappearing after deploy | Expected — edit locally, not in the workspace. |

---

## Conventions

- One resource per file under `resources/`, named after the resource key.
- Keep `src/` free of environment-specific values — use `variables:` and target overrides instead.
- Never commit tokens or secrets. Use Databricks secrets or environment variables.
- Run `validate` and `plan` before opening a pull request.

---

## References

- Declarative Automation Bundles (formerly Asset Bundles): https://docs.databricks.com/aws/en/dev-tools/bundles/
- CLI `bundle` commands: https://docs.databricks.com/aws/en/dev-tools/cli/bundle-commands
- Configuration reference: https://docs.databricks.com/aws/en/dev-tools/bundles/reference
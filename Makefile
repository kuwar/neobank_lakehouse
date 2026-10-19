.PHONY: install test unit integration clean tf-shared-plan tf-shared-apply tf-plan tf-apply dashboards validate deploy

install:
	poetry install

# Everything.
test:
	pytest

# Fast, cluster-free tests only — use this in the main CI job.
unit:
	pytest -m "not integration"

# Tests that read real sample files — separate, slower CI job.
integration:
	pytest -m integration

clean:
	rm -rf .pytest_cache **/__pycache__ .venv

# Infrastructure. TARGET_ENV comes from .env via direnv (dev | prod).
# Order: shared (once per workspace) -> env (catalog, grants, ABAC) -> bundle.
TARGET_ENV ?= dev
TF_ENV := terraform/envs/$(TARGET_ENV)

tf-shared-plan:
	terraform -chdir=terraform/shared plan

tf-shared-apply:
	terraform -chdir=terraform/shared apply

tf-plan:
	terraform -chdir=$(TF_ENV) plan

tf-apply:
	terraform -chdir=$(TF_ENV) apply

# Metric-view datasets need a fully qualified asset_name (dataset_catalog doesn't
# apply to them), so the dashboard edited in dev is rendered per env. The prod
# target reads the rendered file (databricks.yaml).
DASHBOARD_SRC := src/dashboards/neobank_analytics.lvdash.json
DASHBOARD_OUT := build/dashboards/neobank_analytics.$(TARGET_ENV).lvdash.json

dashboards:
	@grep -q '"neobank_dev\.' $(DASHBOARD_SRC) || { echo "$(DASHBOARD_SRC): expected neobank_dev.* references"; exit 1; }
	mkdir -p build/dashboards
	sed 's/"neobank_dev\./"neobank_$(TARGET_ENV)./g' $(DASHBOARD_SRC) > $(DASHBOARD_OUT)

# Bundle. Same commands locally and in CI (.github/workflows/bundle-deploy.yml).
validate: dashboards
	databricks bundle validate -t $(TARGET_ENV)

deploy: dashboards
	databricks bundle deploy -t $(TARGET_ENV)

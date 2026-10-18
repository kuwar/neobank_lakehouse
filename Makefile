.PHONY: install test unit integration clean tf-shared-plan tf-shared-apply tf-plan tf-apply deploy

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

# Bundle target is DATABRICKS_BUNDLE_TARGET, also derived from TARGET_ENV
deploy:
	databricks bundle deploy -t $(TARGET_ENV)

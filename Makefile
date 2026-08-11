.PHONY: install test unit integration clean

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
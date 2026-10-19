# Authenticates from the environment: DATABRICKS_CONFIG_PROFILE in .envrc.
provider "databricks" {}

# Authenticates with GITHUB_TOKEN from .env: a fine-grained token for this repo
# with Administration, Environments, Secrets and Variables read/write.
provider "github" {
  owner = var.github_owner
}

terraform {
  required_version = ">= 1.5"

  required_providers {
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.127.0"
    }
  }

  # State is local to this directory. Before running Terraform from CI, switch to
  # a remote backend with one key per root, for example:
  #   backend "s3" { bucket = "<bucket>", key = "neobank/prod.tfstate", region = "<region>" }
}

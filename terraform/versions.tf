terraform {
  required_version = ">= 1.5"

  required_providers {
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.0" # any 1.x; pin exactly in real projects
    }
  }
}
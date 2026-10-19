# Everything one neobank environment needs in Unity Catalog. Called once per env
# root (envs/dev, envs/prod); var.env is the only input that differs.
#
# Principals come from terraform/shared or the account and are looked up by name,
# so this module never creates anything that exists once per workspace.

locals {
  # Must match the catalog of the bundle target (databricks.yaml).
  catalog = "neobank_${var.env}"

  # The bundle creates the pipeline tables, UDFs and metric views; prod runs as the
  # CI/CD SP.
  bundle_privileges = ["USE_CATALOG", "USE_SCHEMA", "SELECT", "MODIFY", "EXECUTE",
    "CREATE_TABLE", "CREATE_MATERIALIZED_VIEW", "CREATE_FUNCTION",
  "READ_VOLUME", "WRITE_VOLUME"]
}

data "databricks_service_principal" "cicd" {
  display_name = var.cicd_sp_name
}

data "databricks_service_principal" "metabase" {
  display_name = var.metabase_sp_name
}

# Groups are referenced through data sources rather than plain strings, so plan
# fails early if one is missing.
data "databricks_group" "this" {
  for_each     = var.groups
  display_name = each.value
}

locals {
  group = { for k, g in data.databricks_group.this : k => g.display_name }
}

module "catalog" {
  source = "../uc_catalog"

  name    = local.catalog
  comment = "Neobank ${var.env} catalog"

  schemas = {
    bronze       = "Raw data landing zone"
    silver       = "Transformed data landing zone"
    gold         = "Business ready data"
    metrics_view = "Business ready data to query using BI tools - eg. Metabase"
  }

  # Landing zone for the raw files.
  volumes = {
    raw = { schema = "bronze" }
  }

  catalog_grants = {
    (local.group["data_engineers"]) = [
      "USE_CATALOG", "USE_SCHEMA", "SELECT", "MODIFY",
    "CREATE_TABLE", "READ_VOLUME", "WRITE_VOLUME"]
    (data.databricks_service_principal.metabase.application_id) = ["USE_CATALOG"]
    (data.databricks_service_principal.cicd.application_id)     = local.bundle_privileges
  }

  # BI reads the metric views only. The views read gold with their owner's rights,
  # so Metabase needs no grant on gold.
  schema_grants = {
    metrics_view = {
      (data.databricks_service_principal.metabase.application_id) = ["USE_SCHEMA", "SELECT"]
    }
  }
}

# Column tags are assigned by the bundle (src/governance/tag_gold_columns.sql) and
# the tag keys are defined in terraform/shared.
module "abac" {
  source = "../uc_abac_policies"

  schema = module.catalog.schemas["gold"]
  policies = var.enable_abac_policies ? {
    mask_pci_columns = {
      type              = "column_mask"
      tag               = "pci"
      function          = "mask_card_number"
      except_principals = [local.group["pci_readers"]]
    }
    mask_pii_address_columns = {
      type              = "column_mask"
      tag               = "pii"
      function          = "mask_address"
      except_principals = [local.group["pii_readers"]]
    }
    row_filter_region_sensitive = {
      type              = "row_filter"
      tag               = "region_sensitive"
      function          = "filter_by_region"
      except_principals = [local.group["global_analysts"]]
    }
  } : {}
}

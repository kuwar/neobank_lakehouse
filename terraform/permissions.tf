resource "databricks_grants" "neobank_catalog" {
  catalog = databricks_catalog.neobank.name

  grant {
    principal = data.databricks_group.data_engineers.display_name
    privileges = ["USE_CATALOG", "USE_SCHEMA", "SELECT", "MODIFY",
    "CREATE_TABLE", "READ_VOLUME", "WRITE_VOLUME"]
  }
  grant {
    principal  = data.databricks_service_principal.sp_metabase.application_id
    privileges = ["USE_CATALOG"]
  }

  # GitHub CI/CD SP: the prod bundle runs as this SP (run_as), so it builds the
  # pipeline tables, metric views and mask/filter UDFs. Granted on the catalog,
  # so it inherits to every schema (schemas themselves stay Terraform-owned).
  grant {
    principal = databricks_service_principal.sp_cicd.application_id
    privileges = ["USE_CATALOG", "USE_SCHEMA", "SELECT", "MODIFY", "EXECUTE",
      "CREATE_TABLE", "CREATE_MATERIALIZED_VIEW", "CREATE_FUNCTION",
    "READ_VOLUME", "WRITE_VOLUME"]
  }
}

resource "databricks_grants" "neobank_schema" {
  schema = "${databricks_catalog.neobank.name}.${databricks_schema.gold.name}"

  grant {
    principal  = data.databricks_service_principal.sp_metabase.application_id
    privileges = ["USE_SCHEMA", "SELECT"]
  }
}
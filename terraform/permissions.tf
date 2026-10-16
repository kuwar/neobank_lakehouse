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

  # CI/CD SP. The prod bundle runs as this SP, so it creates the tables, MVs
  # and UDFs. Granted at catalog level to cover every schema.
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
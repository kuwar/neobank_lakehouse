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

  grant {
    principal  = data.databricks_group.cicd.display_name
    privileges = ["USE_CATALOG", "CREATE_SCHEMA", "USE_SCHEMA"]
  }
}

resource "databricks_grants" "neobank_schema" {
  schema = "${databricks_catalog.neobank.name}.${databricks_schema.gold.name}"

  grant {
    principal  = data.databricks_service_principal.sp_metabase.application_id
    privileges = ["USE_SCHEMA", "SELECT"]
  }
}
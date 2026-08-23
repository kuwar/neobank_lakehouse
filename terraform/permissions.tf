resource "databricks_grants" "neobank_catalog" {
  catalog = databricks_catalog.neobank.name

  grant {
    principal = databricks_group.data_engineers.display_name
    privileges = ["USE_CATALOG", "USE_SCHEMA", "SELECT", "MODIFY",
    "CREATE_TABLE", "READ_VOLUME", "WRITE_VOLUME"]
  }
  grant {
    principal  = databricks_service_principal.metabase.display_name
    privileges = ["USE_CATALOG"]
  }
}

resource "databricks_grants" "neobank_schema" {
  schema = "${databricks_catalog.neobank.name}.${databricks_schema.gold.name}"

  grant {
    principal  = databricks_service_principal.metabase.display_name
    privileges = ["USE_SCHEMA", "SELECT"]
  }
}
resource "databricks_grants" "neobank_catalog" {
  catalog = databricks_catalog.neobank.name

  grant {
    principal = databricks_group.data_engineers.display_name
    privileges = ["USE_CATALOG", "USE_SCHEMA", "SELECT", "MODIFY",
    "CREATE_TABLE", "READ_VOLUME", "WRITE_VOLUME"]
  }
  grant {
    principal  = databricks_service_principal.metabase_sp.display_name
    privileges = ["USE_CATALOG"]
  }

  grant {
    principal = databricks_group.ci_cd.display_name
    privileges = ["USE_CATALOG", "CREATE_SCHEMA", "USE_SCHEMA"]
  }
}

resource "databricks_grants" "neobank_schema" {
  schema = "${databricks_catalog.neobank.name}.${databricks_schema.gold.name}"

  grant {
    principal  = databricks_service_principal.metabase_sp.display_name
    privileges = ["USE_SCHEMA", "SELECT"]
  }
}
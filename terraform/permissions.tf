# Authoritative grant set on the schema.
# databricks_grants REPLACES all grants on the object with exactly what's listed.
resource "databricks_grants" "neobank_schema" {
  schema = "${databricks_catalog.neobank.name}.${databricks_schema.bronze.name}"

  grant {
    principal  = data.databricks_user.me.user_name
    privileges = ["USE_SCHEMA", "SELECT", "CREATE_TABLE"]
  }
}
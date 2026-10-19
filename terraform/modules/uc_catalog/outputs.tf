output "catalog" {
  value = databricks_catalog.this.name
}

# Schema name => full name (catalog.schema)
output "schemas" {
  value = { for k, s in databricks_schema.this : k => s.id }
}

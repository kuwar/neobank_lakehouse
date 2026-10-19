output "catalog" {
  description = "Catalog name."
  value       = databricks_catalog.this.name
}

output "schemas" {
  description = "Schema name => full name (catalog.schema)."
  value       = { for k, s in databricks_schema.this : k => s.id }
}

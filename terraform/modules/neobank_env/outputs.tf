output "catalog" {
  description = "Catalog name, neobank_<env>."
  value       = module.catalog.catalog
}

output "schemas" {
  description = "Schema name => full name (catalog.schema)."
  value       = module.catalog.schemas
}

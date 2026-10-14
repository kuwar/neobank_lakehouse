# A catalog: the top of the Unity Catalog hierarchy (catalog → schema → tables/views/volumes/functions)
resource "databricks_catalog" "neobank" {
  name    = var.catalog
  comment = "Neobank ${var.env} catalog"

  lifecycle {
    ignore_changes  = [storage_root, properties] # set by Default Storage / Databricks (e.g. collation), not by us
    prevent_destroy = true                       # never let a plan delete this catalog
  }
}

# A schema inside that catalog
resource "databricks_schema" "bronze" {
  catalog_name = databricks_catalog.neobank.name
  name         = "bronze"
  comment      = "Raw data landing zone"
}
resource "databricks_schema" "silver" {
  catalog_name = databricks_catalog.neobank.name
  name         = "silver"
  comment      = "Transformed data landing zone"
}
resource "databricks_schema" "gold" {
  catalog_name = databricks_catalog.neobank.name
  name         = "gold"
  comment      = "Business ready data"
}
resource "databricks_schema" "metrics_view" {
  catalog_name = databricks_catalog.neobank.name
  name         = "metrics_view"
  comment      = "Business ready data to query using BI tools - eg. Metabase"
}

# A managed volume for files (CSVs, models, etc.)
resource "databricks_volume" "raw" {
  catalog_name = databricks_catalog.neobank.name
  schema_name  = databricks_schema.bronze.name
  name         = "raw"
  volume_type  = "MANAGED"
}
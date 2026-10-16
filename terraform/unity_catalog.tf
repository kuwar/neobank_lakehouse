# Free Edition (Default Storage) can't create catalogs through the API. Create it
# with SQL, then import:
#   CREATE CATALOG IF NOT EXISTS neobank_<env>;
#   terraform import databricks_catalog.neobank neobank_<env>
resource "databricks_catalog" "neobank" {
  name    = var.catalog
  comment = "Neobank ${var.env} catalog"

  lifecycle {
    ignore_changes  = [storage_root, properties] # set server-side
    prevent_destroy = true
  }
}

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

# Landing zone for raw files
resource "databricks_volume" "raw" {
  catalog_name = databricks_catalog.neobank.name
  schema_name  = databricks_schema.bronze.name
  name         = "raw"
  volume_type  = "MANAGED"
}
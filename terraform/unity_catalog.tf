# A catalog: the top of the Unity Catalog hierarchy (catalog → schema → table/volume)
resource "databricks_catalog" "neobank" {
  name    = "neobank"
  comment = "Neobank prod catalog"
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

# A managed volume for files (CSVs, models, etc.)
resource "databricks_volume" "raw" {
  catalog_name = databricks_catalog.neobank.name
  schema_name  = databricks_schema.bronze.name
  name         = "raw"
  volume_type  = "MANAGED"
}
data "databricks_group" "pci_readers" {
  display_name = "pci-readers"
}

data "databricks_group" "pii_readers" {
  display_name = "pii-readers"
}

data "databricks_group" "data_engineers" {
  display_name = "data-engineers"
}

data "databricks_group" "global_analysts" {
  display_name = "global-analysts"
}

data "databricks_service_principal" "sp_metabase" {
  display_name = "sp-metabase-reader"
}
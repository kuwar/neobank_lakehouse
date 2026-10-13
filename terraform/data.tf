# Who am I? — used to build the notebook path above
data "databricks_user" "me" {
  user_name = "kuwarsaurav21@gmail.com"
}

data "databricks_group" "pci_readers" {
  display_name = "pci-readers"
}

data "databricks_group" "pii_readers" {
  display_name = "pii-readers"
}

# A group that will act as our "Data Engineers role"
data "databricks_group" "data_engineers" {
  display_name = "data-engineers"
}

data "databricks_group" "global_analysts" {
  display_name = "global-analysts"
}
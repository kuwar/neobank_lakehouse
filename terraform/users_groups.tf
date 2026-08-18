# Two users
resource "databricks_user" "shaurave" {
  provider     = databricks.account
  user_name    = "kuwarsaurav21@gmail.com"
  display_name = "Shaurave KUWAR"
}

# A group that will act as our "Data Engineers role"
resource "databricks_group" "data_engineers" {
  provider     = databricks.account
  display_name = "data_engineers"

  # Entitlements = the coarse "capabilities" half of a role
  allow_cluster_create  = true
  databricks_sql_access = true
  workspace_access      = true
}

# Put Alice in the group
resource "databricks_group_member" "shaurave_eng" {
  provider  = databricks.account
  group_id  = databricks_group.data_engineers.id
  member_id = databricks_user.shaurave.id
}
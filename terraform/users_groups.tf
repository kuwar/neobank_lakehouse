# A group that will act as our "Data Engineers role"
resource "databricks_group" "data_engineers" {
  display_name = "data_engineers"

  # Entitlements = the coarse "capabilities" half of a role
  databricks_sql_access = true
  workspace_access      = true
}

# Put Shaurave in the group
resource "databricks_group_member" "shaurave_eng" {
  group_id  = databricks_group.data_engineers.id
  member_id = data.databricks_user.me.id
}
# resource "databricks_group" "ci_cd" {
#   display_name               = "cicd"
#   allow_cluster_create       = false
#   allow_instance_pool_create = false
# }


resource "databricks_service_principal" "sp_dev" {
  display_name = "Dev SP"
}

# resource "databricks_group_member" "i_am_cicd" {
#   group_id  = databricks_group.ci_cd.id
#   member_id = databricks_service_principal.sp_dev.id
# }



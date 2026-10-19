# Workspace-wide identities: one of each, used by every environment. The env roots
# look them up by name, and their catalog grants live in modules/neobank_env.

# Service principal for bundle deploys from GitHub Actions. It is created through
# the workspace API; with identity federation it is an account-level principal, so
# Unity Catalog grants accept it.
resource "databricks_service_principal" "sp_cicd" {
  display_name = "sp-github-cicd"

  # Workspace access for bundle deploys, SQL access for the warehouse tasks.
  workspace_access      = true
  databricks_sql_access = true
}

# OAuth M2M secret, written to GitHub by github.tf. OIDC federation would avoid it
# but needs the account API, which Free Edition doesn't have.
# Rotate: terraform apply -replace=databricks_service_principal_secret.sp_cicd_secret
resource "databricks_service_principal_secret" "sp_cicd_secret" {
  service_principal_id = databricks_service_principal.sp_cicd.id
}

# sp-metabase-reader is created by hand in the UI; Terraform only creates its secret.
data "databricks_service_principal" "sp_metabase" {
  display_name = "sp-metabase-reader"
}

# Metabase connects with OAuth M2M:
#   host       dbc-31fcc0ce-44e6.cloud.databricks.com
#   HTTP path  /sql/1.0/warehouses/<warehouse-id>
#   auth       outputs sp_metabase_client_id / sp_metabase_client_secret
#   catalog    neobank_<env>, schema metrics_view
resource "databricks_service_principal_secret" "sp_metabase_secret" {
  service_principal_id = data.databricks_service_principal.sp_metabase.id
}

# The warehouse is shared by dev and prod. databricks_permissions is authoritative,
# so this is its only owner.
resource "databricks_permissions" "sql_warehouse" {
  sql_endpoint_id = var.warehouse_id

  access_control {
    service_principal_name = data.databricks_service_principal.sp_metabase.application_id
    permission_level       = "CAN_USE"
  }
  access_control {
    service_principal_name = databricks_service_principal.sp_cicd.application_id
    permission_level       = "CAN_USE"
  }
}

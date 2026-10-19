# Workspace-wide identities: one of each, used by every environment. The env
# roots look these up by name.

# SP for bundle deploys from GitHub Actions. Created through the workspace API;
# with identity federation it's an account-level principal, so UC grants accept it.
# Its catalog grants live with each env (modules/neobank_env).
resource "databricks_service_principal" "sp_cicd" {
  display_name          = "sp-github-cicd"
  workspace_access      = true # bundle deploy
  databricks_sql_access = true # SQL tasks on the warehouse
}

# OAuth M2M secret for GitHub. OIDC federation needs the account API, which
# Free Edition doesn't have.
# Rotate: terraform apply -replace=databricks_service_principal_secret.sp_cicd_secret
resource "databricks_service_principal_secret" "sp_cicd_secret" {
  service_principal_id = databricks_service_principal.sp_cicd.id
}

# sp-metabase-reader is created manually. Its catalog/schema grants live with
# each env (modules/neobank_env).
data "databricks_service_principal" "sp_metabase" {
  display_name = "sp-metabase-reader"
}

resource "databricks_service_principal_secret" "sp_metabase_secret" {
  service_principal_id = data.databricks_service_principal.sp_metabase.id
}

# The warehouse is shared by dev and prod. databricks_permissions is
# authoritative, so it must have exactly one owner: this file.
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

# Metabase connection:
#   host:      dbc-31fcc0ce-44e6.cloud.databricks.com
#   HTTP path: /sql/1.0/warehouses/<warehouse-id>
#   auth:      OAuth M2M, outputs sp_metabase_client_id / sp_metabase_client_secret
#   catalog:   neobank_<env>

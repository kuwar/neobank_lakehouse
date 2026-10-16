# SP for bundle deploys from GitHub Actions. Created through the workspace API;
# with identity federation it's an account-level principal, so UC grants accept it.
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

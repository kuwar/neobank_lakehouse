# Service principal used by GitHub Actions to deploy the bundle (databricks bundle deploy/run).
# Created from the workspace provider: with identity federation it lands at account level,
# so it can be used in Unity Catalog grants.
resource "databricks_service_principal" "sp_cicd" {
  display_name          = "sp-github-cicd"
  workspace_access      = true # deploy bundle files, create jobs/pipelines
  databricks_sql_access = true # run the SQL tasks (UDF job) on the warehouse
}

# OAuth M2M secret for GitHub. Free Edition has no account API, so GitHub OIDC
# federation isn't available; store client id + secret as GitHub repo secrets.
# To rotate: terraform apply -replace=databricks_service_principal_secret.sp_cicd_secret
resource "databricks_service_principal_secret" "sp_cicd_secret" {
  service_principal_id = databricks_service_principal.sp_cicd.id
}

# Kaggle secret scope, read by the land_data task to download the dataset.
# Dev and prod share this scope (bundle variable kaggle_secret_scope).
#
# The token is taken from KAGGLE_API_TOKEN in .env (.envrc passes it to Terraform).
# To rotate it, update .env and run `make tf-shared-apply`.

resource "databricks_secret_scope" "kaggle" {
  name = "kaggle"
}

resource "databricks_secret" "kaggle_api_token" {
  scope        = databricks_secret_scope.kaggle.name
  key          = "api_token"
  string_value = var.kaggle_api_token
}

# Prod jobs run as sp-github-cicd, so it needs to read the token.
# Without this the Kaggle download is skipped but the job still passes.
resource "databricks_secret_acl" "kaggle_sp_cicd" {
  scope      = databricks_secret_scope.kaggle.name
  principal  = databricks_service_principal.sp_cicd.application_id
  permission = "READ"
}

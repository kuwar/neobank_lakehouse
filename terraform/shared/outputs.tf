output "sp_metabase_client_id" {
  value = data.databricks_service_principal.sp_metabase.application_id
}

output "sp_metabase_client_secret" {
  value     = databricks_service_principal_secret.sp_metabase_secret.secret
  sensitive = true
}

# GitHub secret DATABRICKS_CLIENT_ID
output "sp_cicd_client_id" {
  value = databricks_service_principal.sp_cicd.application_id
}

# GitHub secret DATABRICKS_CLIENT_SECRET
output "sp_cicd_client_secret" {
  value     = databricks_service_principal_secret.sp_cicd_secret.secret
  sensitive = true
}

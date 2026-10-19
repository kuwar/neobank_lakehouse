output "sp_metabase_client_id" {
  description = "OAuth client ID for the Metabase connection."
  value       = data.databricks_service_principal.sp_metabase.application_id
}

output "sp_metabase_client_secret" {
  description = "OAuth secret for the Metabase connection."
  value       = databricks_service_principal_secret.sp_metabase_secret.secret
  sensitive   = true
}

output "sp_cicd_client_id" {
  description = "Application ID of sp-github-cicd. Its secret goes to GitHub only (github.tf)."
  value       = databricks_service_principal.sp_cicd.application_id
}

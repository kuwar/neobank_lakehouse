# GitHub Actions configuration for .github/workflows/bundle-deploy.yml. The CI/CD
# SP secret from service_principals.tf is written straight to GitHub, so setup and
# rotation are a single apply. Terraform is the only creator: don't add these
# settings in the GitHub UI.

locals {
  github_environments = toset(["dev", "prod"])

  # Only the credentials are needed: the host comes from databricks.yaml and the
  # target from TARGET_ENV in the workflow.
  github_env_secrets = {
    for pair in setproduct(local.github_environments, ["DATABRICKS_CLIENT_ID", "DATABRICKS_CLIENT_SECRET"]) :
    "${pair[0]}/${pair[1]}" => { environment = pair[0], name = pair[1] }
  }
  github_secret_values = {
    DATABRICKS_CLIENT_ID     = databricks_service_principal.sp_cicd.application_id
    DATABRICKS_CLIENT_SECRET = databricks_service_principal_secret.sp_cicd_secret.secret
  }
}

data "github_user" "prod_reviewers" {
  for_each = toset(var.prod_reviewers)
  username = each.value
}

# Environment protection rules (reviewers, branch rules) are free on public repos.
resource "github_repository_environment" "this" {
  for_each    = local.github_environments
  repository  = var.github_repository
  environment = each.key

  dynamic "reviewers" {
    for_each = each.key == "prod" && length(var.prod_reviewers) > 0 ? [1] : []
    content {
      users = [for u in data.github_user.prod_reviewers : tonumber(u.id)]
    }
  }

  # Only main can deploy to prod. Dev stays open so PRs from any branch validate.
  dynamic "deployment_branch_policy" {
    for_each = each.key == "prod" ? [1] : []
    content {
      protected_branches     = false
      custom_branch_policies = true
    }
  }
}

resource "github_repository_environment_deployment_policy" "prod_main" {
  repository     = var.github_repository
  environment    = github_repository_environment.this["prod"].environment
  branch_pattern = "main"
}

resource "github_actions_environment_secret" "databricks" {
  for_each = local.github_env_secrets

  repository  = var.github_repository
  environment = github_repository_environment.this[each.value.environment].environment
  secret_name = each.value.name
  value       = local.github_secret_values[each.value.name]
}

# A repository variable, not an environment one: the deploy-prod job's `if:` is
# evaluated before the job loads its environment.
resource "github_actions_variable" "prod_deploy_enabled" {
  repository    = var.github_repository
  variable_name = "PROD_DEPLOY_ENABLED"
  value         = tostring(var.prod_deploy_enabled)
}

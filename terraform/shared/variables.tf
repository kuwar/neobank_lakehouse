variable "warehouse_id" {
  description = "SQL warehouse ID (16 hex characters, not the workspace ID)."
  type        = string
  sensitive   = true
}

variable "slack_webhook_url" {
  description = "Slack incoming webhook for slack_neobank. Set as TF_VAR_slack_webhook_url in .env."
  type        = string
  sensitive   = true
}

variable "databricks_account_id" {
  description = "Databricks account ID, used in the governed tag rule set names. Shown by `databricks auth describe`."
  type        = string
}

variable "email_notification_addresses" {
  description = "Email addresses for the neobank_email_notification destination."
  type        = list(string)
  default     = []
}

variable "github_owner" {
  description = "GitHub user or organisation that owns the repository."
  type        = string
  default     = "kuwar"
}

variable "github_repository" {
  description = "Repository the CI/CD settings are written to."
  type        = string
  default     = "neobank_lakehouse"
}

variable "prod_deploy_enabled" {
  description = "Repository variable PROD_DEPLOY_ENABLED. false pauses CI deploys to prod."
  type        = bool
  default     = true
}

variable "prod_reviewers" {
  description = "GitHub usernames that must approve each prod deploy. Empty: no approval."
  type        = list(string)
  default     = []
}

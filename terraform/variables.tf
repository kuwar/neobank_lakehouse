variable "databricks_host" {
  type = string
}

variable "databricks_token" {
  type      = string
  sensitive = true
}

variable "workspace_id" {
  type      = string
  sensitive = true
}

variable "metastore_id" {
  type      = string
  sensitive = true
}

variable "warehouse_id" {
  type      = string
  sensitive = true
}

variable "slack_webhook_url" {
  type      = string
  sensitive = true
}

variable "email_notification_addresses" {
  type        = list(string)
  description = "List of email addresses for the notification destination"
  default     = []
}
variable "enable_abac_policies" {
  description = "Create ABAC column tag assignments and policies. Turn on only after the bundle has created the mask/filter UDFs and the gold tables (see README deploy order)."
  type        = bool
  default     = false
}

variable "env" {
  description = "Target environment (dev | prod). Set via TARGET_ENV in .env → TF_VAR_env (.envrc)."
  type        = string
  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env must be dev or prod."
  }
}

variable "catalog" {
  description = "Unity Catalog catalog for this environment (neobank_<env>). Set via .envrc → TF_VAR_catalog; shared with the bundle's $${var.catalog}."
  type        = string
}

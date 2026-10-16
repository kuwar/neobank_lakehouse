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
  description = "Create the ABAC policies. Needs the mask/filter UDFs from job neobank_security_functions."
  type        = bool
  default     = false
}

variable "env" {
  description = "dev or prod. Set from TARGET_ENV via .envrc."
  type        = string
  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env must be dev or prod."
  }
}

variable "catalog" {
  description = "Catalog name, neobank_<env>. Set via .envrc; the bundle uses the same value."
  type        = string
}

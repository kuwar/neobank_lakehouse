variable "warehouse_id" {
  type      = string
  sensitive = true
}

# Set in .env as TF_VAR_slack_webhook_url
variable "slack_webhook_url" {
  type      = string
  sensitive = true
}

variable "email_notification_addresses" {
  type        = list(string)
  description = "List of email addresses for the notification destination"
  default     = []
}

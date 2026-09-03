variable "databricks_host" {
  type = string
}

variable "databricks_token" {
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
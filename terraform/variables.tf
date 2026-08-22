
variable "account_client_secret" {
  type      = string
  sensitive = true
  default   = ""
}

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
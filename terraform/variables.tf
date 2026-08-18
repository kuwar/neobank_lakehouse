variable "databricks_account_id" {
  type = string
}
variable "account_client_id" {
  type      = string
  sensitive = true
}
variable "account_client_secret" {
  type      = string
  sensitive = true
}
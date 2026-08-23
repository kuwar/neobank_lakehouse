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
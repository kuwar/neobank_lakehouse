variable "name" {
  description = "Catalog name."
  type        = string
}

variable "comment" {
  description = "Catalog comment shown in Catalog Explorer."
  type        = string
  default     = null
}

variable "schemas" {
  description = "Schema name => comment."
  type        = map(string)
}

variable "volumes" {
  description = "Managed volume name => the schema it lives in and an optional comment."
  type = map(object({
    schema  = string
    comment = optional(string)
  }))
  default = {}
}

variable "catalog_grants" {
  description = "Principal => privileges on the catalog. Authoritative: other grants are revoked."
  type        = map(list(string))
  default     = {}
}

variable "schema_grants" {
  description = "Schema name => (principal => privileges). Authoritative per schema."
  type        = map(map(list(string)))
  default     = {}
}

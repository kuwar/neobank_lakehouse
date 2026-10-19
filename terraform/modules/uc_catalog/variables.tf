variable "name" {
  description = "Catalog name"
  type        = string
}

variable "comment" {
  type    = string
  default = null
}

variable "schemas" {
  description = "Schema name => comment"
  type        = map(string)
}

variable "volumes" {
  description = "Managed volume name => schema it lives in"
  type = map(object({
    schema  = string
    comment = optional(string)
  }))
  default = {}
}

variable "catalog_grants" {
  description = "Principal => privileges on the catalog (authoritative)"
  type        = map(list(string))
  default     = {}
}

variable "schema_grants" {
  description = "Schema name => (principal => privileges) (authoritative per schema)"
  type        = map(map(list(string)))
  default     = {}
}

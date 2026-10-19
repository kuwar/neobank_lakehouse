variable "schema" {
  description = "Full schema name (catalog.schema) the policies attach to; UDFs live here too"
  type        = string
}

variable "policies" {
  description = "Policy name => definition. function is the UDF name inside var.schema."
  type = map(object({
    type              = string # column_mask | row_filter
    tag               = string # governed tag key the columns carry
    function          = string
    to_principals     = optional(list(string), ["account users"])
    except_principals = optional(list(string), [])
  }))
  default = {}

  validation {
    condition     = alltrue([for p in values(var.policies) : contains(["column_mask", "row_filter"], p.type)])
    error_message = "policy type must be column_mask or row_filter."
  }
}

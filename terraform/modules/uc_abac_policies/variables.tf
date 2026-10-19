variable "schema" {
  description = "Full schema name (catalog.schema) the policies attach to. The UDFs live here too."
  type        = string
}

variable "policies" {
  description = <<-EOT
    Policy name => definition:
      type              column_mask or row_filter
      tag               governed tag key the matched columns carry
      function          UDF name inside var.schema
      to_principals     who the policy applies to (default: account users)
      except_principals who is exempt
  EOT
  type = map(object({
    type              = string
    tag               = string
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

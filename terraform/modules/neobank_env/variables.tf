variable "env" {
  description = "dev or prod"
  type        = string
  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env must be dev or prod."
  }
}

variable "enable_abac_policies" {
  description = "Create the ABAC policies. Needs the mask/filter UDFs from job neobank_security_functions."
  type        = bool
  default     = false
}

# Created in terraform/shared
variable "cicd_sp_name" {
  type    = string
  default = "sp-github-cicd"
}

# Created by hand (see terraform/shared/service_principals.tf)
variable "metabase_sp_name" {
  type    = string
  default = "sp-metabase-reader"
}

# Account-level groups. Free Edition can't manage membership from Terraform.
variable "groups" {
  type = object({
    data_engineers  = optional(string, "data-engineers")
    pci_readers     = optional(string, "pci-readers")
    pii_readers     = optional(string, "pii-readers")
    global_analysts = optional(string, "global-analysts")
  })
  default = {}
}

variable "env" {
  description = "Environment name: dev or prod. Sets the catalog name, neobank_<env>."
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

variable "cicd_sp_name" {
  description = "Display name of the CI/CD service principal created in terraform/shared."
  type        = string
  default     = "sp-github-cicd"
}

variable "metabase_sp_name" {
  description = "Display name of the Metabase service principal, created by hand in the UI."
  type        = string
  default     = "sp-metabase-reader"
}

variable "groups" {
  description = "Account-level group names. Created and filled by hand: Free Edition has no account API."
  type = object({
    data_engineers  = optional(string, "data-engineers")
    pci_readers     = optional(string, "pci-readers")
    pii_readers     = optional(string, "pii-readers")
    global_analysts = optional(string, "global-analysts")
  })
  default = {}
}

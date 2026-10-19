# Governed tag definitions. Tag keys are unique account-wide, so they can't be per
# environment. The bundle tags the columns (src/governance/tag_gold_columns.sql)
# because the pipeline owns the tables; the ABAC policies live in modules/neobank_env.

locals {
  # Tag key => description. Each tag allows the values "true" and "false";
  # region_sensitive drives the row filter.
  governed_tags = {
    pii              = "Indicates column contains personal data"
    pci              = "Indicates column contains cardholder data"
    region_sensitive = "Indicates column contains region sensitive data"
  }
}

resource "databricks_tag_policy" "governed" {
  for_each = local.governed_tags

  tag_key     = each.key
  description = each.value
  values = [
    { name = "true" },
    { name = "false" },
  ]
}

# The Terraform runner, kept as manager of each tag below.
data "databricks_current_user" "me" {}

# Governed tags have their own permissions. In prod the bundle tags columns as the
# CI/CD SP (task tag_gold_columns), which needs ASSIGN on each tag as well as
# APPLY TAG on the tables it owns. A rule set replaces every grant on its tag, so
# the Terraform runner is listed as manager to keep access.
resource "databricks_access_control_rule_set" "governed_tag" {
  for_each = databricks_tag_policy.governed

  name = "accounts/${var.databricks_account_id}/tagPolicies/${each.value.id}/ruleSets/default"

  grant_rules {
    principals = [data.databricks_current_user.me.acl_principal_id]
    role       = "roles/tagPolicy.manager"
  }

  grant_rules {
    principals = [databricks_service_principal.sp_cicd.acl_principal_id]
    role       = "roles/tagPolicy.assigner"
  }
}

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

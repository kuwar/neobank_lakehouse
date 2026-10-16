# Tag definitions only. Columns are tagged by the bundle
# (src/governance/tag_gold_columns.sql) since the pipeline owns the tables.
locals {
  # key => description; each tag allows "true" / "false"
  governed_tags = {
    pii              = "Indicates column contains personal data"
    pci              = "Indicates column contains cardholder data"
    region_sensitive = "Indicates column contains region sensitive data" # used by the row filter
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


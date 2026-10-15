# Governed tag definitions (the vocabulary). Terraform owns these; the bundle assigns
# them to columns (src/governance/tag_gold_columns.sql, task tag_gold_columns in
# neobank_daily), because the pipeline owns the tables and their columns.
locals {
  # Governed tags: tag key → description. Each allows the values "true" / "false".
  governed_tags = {
    pii              = "Indicates column contains personal data"
    pci              = "Indicates column contains cardholder data"
    region_sensitive = "Indicates column contains region sensitive data" # drives the row-level filter
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


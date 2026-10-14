locals {
  # Governed tags: tag key → description. Each allows the values "true" / "false".
  governed_tags = {
    pii              = "Indicates column contains personal data"
    pci              = "Indicates column contains cardholder data"
    region_sensitive = "Indicates column contains region sensitive data" # drives the row-level filter
  }

  # Column tag assignments in the gold schema: "<table>.<column>" → tag key (value "true").
  gold_column_tags = {
    "dim_cards.card_number"       = "pci"
    "dim_users.address"           = "pii"
    "dim_merchant.merchant_state" = "region_sensitive"
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

# Needs the gold tables to exist, so it is gated with the ABAC policies (see README deploy order).
resource "databricks_entity_tag_assignment" "gold_column" {
  for_each = var.enable_abac_policies ? local.gold_column_tags : {}

  entity_type = "columns"
  entity_name = "${databricks_catalog.neobank.name}.${databricks_schema.gold.name}.${each.key}"
  tag_key     = databricks_tag_policy.governed[each.value].tag_key
  tag_value   = "true"
}

# The tag policies were individual resources before; keep them instead of recreating.
moved {
  from = databricks_tag_policy.pii
  to   = databricks_tag_policy.governed["pii"]
}
moved {
  from = databricks_tag_policy.pci
  to   = databricks_tag_policy.governed["pci"]
}
moved {
  from = databricks_tag_policy.region_sensitive
  to   = databricks_tag_policy.governed["region_sensitive"]
}

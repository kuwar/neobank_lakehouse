resource "databricks_tag_policy" "pii" {
  tag_key     = "pii"
  description = "Indicates column contains personal data"
  values = [
    {
      name = "true"
    },
    {
      name = "false"
    }
  ]
}

resource "databricks_tag_policy" "pci" {
  tag_key     = "pci"
  description = "Indicates column contains cardholder data"
  values = [
    {
      name = "true"
    },
    {
      name = "false"
    }
  ]
}

resource "databricks_entity_tag_assignment" "card_number_pci" {
  entity_type = "columns"
  entity_name = "${databricks_catalog.neobank.name}.${databricks_schema.gold.name}.dim_cards.card_number"
  tag_key     = "pci"
  tag_value   = "true"
  depends_on  = [databricks_tag_policy.pci]
}

resource "databricks_entity_tag_assignment" "address_pii" {
  entity_type = "columns"
  entity_name = "${databricks_catalog.neobank.name}.${databricks_schema.gold.name}.dim_users.address"
  tag_key     = "pii"
  tag_value   = "true"
  depends_on  = [databricks_tag_policy.pii]
}

# Region sensitive -- row-level-filter
resource "databricks_tag_policy" "region_sensitive" {
  tag_key     = "region_sensitive"
  description = "Indicates column contains region sensitive data"
  values = [
    {
      name = "true"
    },
    {
      name = "false"
    }
  ]
}

resource "databricks_entity_tag_assignment" "merchant_state_region_sensitive" {
  entity_type = "columns"
  entity_name = "${databricks_catalog.neobank.name}.${databricks_schema.gold.name}.dim_merchant.merchant_state"
  tag_key     = "region_sensitive"
  tag_value   = "true"
  depends_on  = [databricks_tag_policy.region_sensitive]
}
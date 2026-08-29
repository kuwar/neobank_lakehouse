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
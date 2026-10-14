resource "databricks_policy_info" "mask_pci_columns" {
  count = var.enable_abac_policies ? 1 : 0

  name                  = "mask_pci_columns"
  on_securable_type     = "SCHEMA"
  on_securable_fullname = "${databricks_catalog.neobank.name}.${databricks_schema.gold.name}"
  for_securable_type    = "TABLE"
  policy_type           = "POLICY_TYPE_COLUMN_MASK"

  to_principals     = ["account users"]
  except_principals = ["${data.databricks_group.pci_readers.display_name}"]

  # Condition for when the policy applies
  when_condition = "hasTag('pci')"

  # Match specific columns
  match_columns = [
    {
      condition = "hasTag('pci')"
      alias     = "pci_col"
    }
  ]

  column_mask = {
    function_name = "${databricks_catalog.neobank.name}.${databricks_schema.gold.name}.mask_card_number"
    on_column     = "pci_col"
  }

}


resource "databricks_policy_info" "mask_pii_address_columns" {
  count = var.enable_abac_policies ? 1 : 0

  name                  = "mask_pii_address_columns"
  on_securable_type     = "SCHEMA"
  on_securable_fullname = "${databricks_catalog.neobank.name}.${databricks_schema.gold.name}"
  for_securable_type    = "TABLE"
  policy_type           = "POLICY_TYPE_COLUMN_MASK"

  to_principals     = ["account users"]
  except_principals = ["${data.databricks_group.pii_readers.display_name}"]

  # Condition for when the policy applies
  when_condition = "hasTag('pii')"

  # Match specific columns
  match_columns = [
    {
      condition = "hasTag('pii')"
      alias     = "pii_col"
    }
  ]

  column_mask = {
    function_name = "${databricks_catalog.neobank.name}.${databricks_schema.gold.name}.mask_address"
    on_column     = "pii_col"
  }

}


resource "databricks_policy_info" "row_filter_region_sensitive" {
  count = var.enable_abac_policies ? 1 : 0

  name                  = "row_filter_region_sensitive"
  on_securable_type     = "SCHEMA"
  on_securable_fullname = "${databricks_catalog.neobank.name}.${databricks_schema.gold.name}"
  for_securable_type    = "TABLE"
  policy_type           = "POLICY_TYPE_ROW_FILTER"

  to_principals     = ["account users"]
  except_principals = ["${data.databricks_group.global_analysts.display_name}"]

  # Condition for when the policy applies
  when_condition = "hasTag('region_sensitive')"

  # Match specific columns
  match_columns = [
    {
      condition = "hasTag('region_sensitive')"
      alias     = "region_sensitive_col"
    }
  ]

  row_filter = {
    function_name = "${databricks_catalog.neobank.name}.${databricks_schema.gold.name}.filter_by_region"
    using = [
      {
        alias = "region_sensitive_col"
      }
    ]
  }

}
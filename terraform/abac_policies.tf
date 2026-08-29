resource "databricks_policy_info" "mask_pci_columns" {
  name                  = "mask_pci_columns"
  on_securable_type     = "SCHEMA"
  on_securable_fullname = "${databricks_catalog.neobank.name}.${databricks_schema.gold.name}"
  for_securable_type    = "TABLE"
  policy_type           = "POLICY_TYPE_COLUMN_MASK"

  to_principals     = ["account users"]
  except_principals = ["pci_readers"]

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
    function_name = "${databricks_catalog.neobank.name}.${databricks_schema.gold.name}.mask_generic_pci"
    on_column     = "pci_col"
  }

}
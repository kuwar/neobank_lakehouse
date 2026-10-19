# Generic building block: tag-driven ABAC policies on one schema. Each policy
# matches columns by governed tag and applies a mask or row-filter UDF.
#
# Unity Catalog rejects a policy whose UDF doesn't exist yet, so the UDFs (bundle
# job neobank_security_functions) must be deployed before these are created.
resource "databricks_policy_info" "this" {
  for_each = var.policies

  name                  = each.key
  on_securable_type     = "SCHEMA"
  on_securable_fullname = var.schema
  for_securable_type    = "TABLE"
  policy_type           = each.value.type == "column_mask" ? "POLICY_TYPE_COLUMN_MASK" : "POLICY_TYPE_ROW_FILTER"

  to_principals     = each.value.to_principals
  except_principals = each.value.except_principals

  match_columns = [
    {
      condition = "hasTag('${each.value.tag}')"
      alias     = "${each.value.tag}_col"
    }
  ]

  column_mask = each.value.type == "column_mask" ? {
    function_name = "${var.schema}.${each.value.function}"
    on_column     = "${each.value.tag}_col"
  } : null

  row_filter = each.value.type == "row_filter" ? {
    function_name = "${var.schema}.${each.value.function}"
    using         = [{ alias = "${each.value.tag}_col" }]
  } : null
}

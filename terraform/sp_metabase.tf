# resource "databricks_service_principal" "sp_metabase" {
#   display_name = "sp-metabase-reader"

#   # entitlements
#   # databricks_sql_access = true
#   # workspace_access      = true
#   # allow_cluster_create  = false
# }

# USE_CATALOG on neobank lives in permissions.tf (databricks_grants.neobank_catalog).
# databricks_grants is authoritative per securable, so only one resource may manage the catalog.

resource "databricks_grants" "metrics_view" {
  schema = "${databricks_catalog.neobank.name}.${databricks_schema.metrics_view.name}"
  grant {
    principal  = data.databricks_service_principal.sp_metabase.application_id
    privileges = ["USE_SCHEMA", "SELECT"]
  }
}

resource "databricks_permissions" "sql_warehouse_metabase" {
  sql_endpoint_id = var.warehouse_id
  access_control {
    service_principal_name = data.databricks_service_principal.sp_metabase.application_id
    permission_level       = "CAN_USE"
  }
}

resource "databricks_service_principal_secret" "sp_metabase_secret" {
  service_principal_id = data.databricks_service_principal.sp_metabase.id
}

# What you plug into Metabase

# Server hostname: workspace URL (<workspace-id>.gcp.databricks.com)
# HTTP path: the SQL warehouse's HTTP path (/sql/1.0/warehouses/<warehouse-id>)
# Auth method: toggle to OAuth M2M
# Client ID: sp_metabase_client_id output
# Client secret: sp_metabase_secret output
# Default catalog: neobank
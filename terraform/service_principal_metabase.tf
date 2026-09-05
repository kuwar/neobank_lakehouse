resource "databricks_service_principal" "metabase_sp" {
  display_name = "sp-metabase-reader"

  # entitlements
  # databricks_sql_access = true
  # workspace_access      = true
  # allow_cluster_create  = false
}

resource "databricks_grants" "catalog_neobank" {
  catalog = databricks_catalog.neobank.name

  grant {
    principal  = databricks_service_principal.metabase_sp.application_id
    privileges = ["USE_CATALOG"]
  }
}

resource "databricks_grants" "metrics_view" {
  schema = "${databricks_catalog.neobank.name}.${databricks_schema.metrics_view.name}"
  grant {
    principal  = databricks_service_principal.metabase_sp.application_id
    privileges = ["USE_SCHEMA", "SELECT"]
  }
}

resource "databricks_permissions" "sql_warehouse_metabase" {
  sql_endpoint_id = var.warehouse_id
  access_control {
    service_principal_name = databricks_service_principal.metabase_sp.application_id
    permission_level       = "CAN_USE"
  }
}

resource "databricks_service_principal_secret" "metabase_sp_secret" {
  service_principal_id = databricks_service_principal.metabase_sp.id
}

# What you plug into Metabase

# Server hostname: workspace URL (<workspace-id>.gcp.databricks.com)
# HTTP path: the SQL warehouse's HTTP path (/sql/1.0/warehouses/<warehouse-id>)
# Auth method: toggle to OAuth M2M
# Client ID: metabase_sp_client_id output
# Client secret: metabase_sp_secret output
# Default catalog: neobank
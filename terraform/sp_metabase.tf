# sp-metabase-reader is created manually (see data.tf). Its USE_CATALOG grant is
# in permissions.tf: databricks_grants is authoritative, one resource per securable.

resource "databricks_grants" "metrics_view" {
  schema = "${databricks_catalog.neobank.name}.${databricks_schema.metrics_view.name}"
  grant {
    principal  = data.databricks_service_principal.sp_metabase.application_id
    privileges = ["USE_SCHEMA", "SELECT"]
  }
}

# Authoritative for the warehouse; add any other principal that needs it here.
resource "databricks_permissions" "sql_warehouse_metabase" {
  sql_endpoint_id = var.warehouse_id
  access_control {
    service_principal_name = data.databricks_service_principal.sp_metabase.application_id
    permission_level       = "CAN_USE"
  }
  access_control {
    service_principal_name = databricks_service_principal.sp_cicd.application_id
    permission_level       = "CAN_USE"
  }
}

resource "databricks_service_principal_secret" "sp_metabase_secret" {
  service_principal_id = data.databricks_service_principal.sp_metabase.id
}

# Metabase connection:
#   host:      dbc-31fcc0ce-44e6.cloud.databricks.com
#   HTTP path: /sql/1.0/warehouses/<warehouse-id>
#   auth:      OAuth M2M, outputs sp_metabase_client_id / sp_metabase_client_secret
#   catalog:   neobank_<env>
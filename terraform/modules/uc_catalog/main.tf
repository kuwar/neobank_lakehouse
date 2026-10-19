# Generic building block: one catalog, its schemas and volumes, and the grants on
# them. It knows nothing about neobank; callers pass names and principals.

# Free Edition (Default Storage) can't create catalogs through the API. The catalog
# is created with SQL and adopted by the import block in envs/<env>/main.tf.
resource "databricks_catalog" "this" {
  name    = var.name
  comment = var.comment

  lifecycle {
    # Both are filled in server-side; a diff on storage_root would force replacement.
    ignore_changes  = [storage_root, properties]
    prevent_destroy = true
  }
}

resource "databricks_schema" "this" {
  for_each = var.schemas

  catalog_name = databricks_catalog.this.name
  name         = each.key
  comment      = each.value
}

resource "databricks_volume" "this" {
  for_each = var.volumes

  catalog_name = databricks_catalog.this.name
  schema_name  = databricks_schema.this[each.value.schema].name
  name         = each.key
  volume_type  = "MANAGED"
  comment      = each.value.comment
}

# databricks_grants is authoritative: anything granted outside Terraform on these
# securables is revoked on the next apply, so all grants belong here.
resource "databricks_grants" "catalog" {
  count   = length(var.catalog_grants) > 0 ? 1 : 0
  catalog = databricks_catalog.this.name

  dynamic "grant" {
    for_each = var.catalog_grants
    content {
      principal  = grant.key
      privileges = grant.value
    }
  }
}

resource "databricks_grants" "schema" {
  for_each = var.schema_grants
  schema   = databricks_schema.this[each.key].id

  dynamic "grant" {
    for_each = each.value
    content {
      principal  = grant.key
      privileges = grant.value
    }
  }
}

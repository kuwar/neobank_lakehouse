# Root for the dev environment: its own state and its own catalog, neobank_dev.
# Apply terraform/shared first, then run: make tf-plan / make tf-apply (TARGET_ENV=dev).

locals {
  env = "dev"
}

module "neobank" {
  source = "../../modules/neobank_env"

  env                  = local.env
  enable_abac_policies = var.enable_abac_policies
}

# Free Edition can't create catalogs through the API. Create it once with SQL,
#   CREATE CATALOG IF NOT EXISTS neobank_dev;
# and this block adopts it on the first apply. It is a no-op afterwards, and plan
# fails until the catalog exists.
import {
  to = module.neobank.module.catalog.databricks_catalog.this
  id = "neobank_${local.env}"
}

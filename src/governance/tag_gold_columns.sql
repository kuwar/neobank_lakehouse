-- Classify sensitive gold columns with governed tags. The Terraform ABAC policies
-- (terraform/abac_policies.tf) mask / filter every column carrying these tags.
--
-- Runs in neobank_daily right after build_medallion, so the tables always exist.
-- Safe to rerun: SET TAGS just overwrites the same value.
-- Tag keys and allowed values are governed tags defined in terraform/abac_tags.tf.
-- ALTER TABLE works for both tables and materialized views.
--
-- Adding a sensitive column to gold? Tag it here in the same PR.

-- PCI: cardholder data → mask_pci_columns
ALTER TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.dim_cards')
  ALTER COLUMN card_number SET TAGS ('pci' = 'true');

-- PII: personal data → mask_pii_address_columns
ALTER TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.dim_users')
  ALTER COLUMN address SET TAGS ('pii' = 'true');

-- Region-sensitive → row_filter_region_sensitive
ALTER TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.dim_merchant')
  ALTER COLUMN merchant_state SET TAGS ('region_sensitive' = 'true');

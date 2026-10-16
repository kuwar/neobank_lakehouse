-- Governed tags on sensitive gold columns. The ABAC policies in
-- terraform/abac_policies.tf mask/filter anything carrying these tags.
-- Runs after build_medallion in neobank_daily; idempotent.
-- Tag keys are defined in terraform/abac_tags.tf.
-- New sensitive gold columns need a line here.

-- pci: mask_pci_columns
ALTER TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.dim_cards')
  ALTER COLUMN card_number SET TAGS ('pci' = 'true');

-- pii: mask_pii_address_columns
ALTER TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.dim_users')
  ALTER COLUMN address SET TAGS ('pii' = 'true');

-- region_sensitive: row_filter_region_sensitive
ALTER TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.dim_merchant')
  ALTER COLUMN merchant_state SET TAGS ('region_sensitive' = 'true');

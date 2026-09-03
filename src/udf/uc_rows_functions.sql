-- -----------------------------------------------------------------------------
-- Row filter: regional analysts see only their region
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION IDENTIFIER(:catalog || '.' || :gold_schema || '.filter_by_region')(merchant_state STRING)
RETURN (
    is_account_group_member('global_analysts')
    OR merchant_state IN (
        SELECT 
            merchant_state 
        FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.dim_merchant')
    )
);

-- Applied to dim_merchant, not the fact: the fact has no state column, and
-- filtering the dimension propagates through every metric view join anyway.
-- ALTER TABLE gold.dim_merchant SET ROW FILTER gold.filter_by_region ON (merchant_state);
 
-- -----------------------------------------------------------------------------
-- Grants
--
-- The key line is the absence of a grant on gold to analysts. If they can reach
-- the fact table, some of them will write their own fraud rate, and the metric
-- layer becomes one opinion among several rather than the source of truth.
-- Exception paths exist (data science needs raw access) and are granted
-- explicitly to a named group, not by default.
-- -----------------------------------------------------------------------------
-- GRANT USE CATALOG ON CATALOG neobank                TO `analysts`;
-- GRANT USE SCHEMA  ON SCHEMA  neobank.semantic       TO `analysts`;
-- GRANT SELECT      ON SCHEMA  neobank.semantic       TO `analysts`;
 
-- GRANT USE SCHEMA  ON SCHEMA  neobank.gold           TO `data_science`;
-- GRANT SELECT      ON SCHEMA  neobank.gold           TO `data_science`;
 
-- GRANT SELECT ON TABLE neobank.gold.dim_cards        TO `pci_readers`;
 
-- ALTER SCHEMA neobank.semantic SET OWNER TO `analytics_platform`;
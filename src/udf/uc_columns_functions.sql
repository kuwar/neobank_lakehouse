-- Column masks. Who sees the raw value is decided by the ABAC policy
-- (terraform/abac_policies.tf, except_principals), not here: exempt groups never
-- reach the function, so each mask just returns the masked value.

-- Mask the card number: keep the last 4 digits
CREATE OR REPLACE FUNCTION IDENTIFIER(:catalog || '.' || :gold_schema || '.mask_card_number')(card_number BIGINT)
RETURN CAST(RIGHT(CAST(card_number AS STRING), 4) AS BIGINT);

CREATE OR REPLACE FUNCTION IDENTIFIER(:catalog || '.' || :gold_schema || '.mask_cvv')(cvv INT)
RETURN CAST(NULL AS INT);

CREATE OR REPLACE FUNCTION IDENTIFIER(:catalog || '.' || :gold_schema || '.mask_coordinate')(coord DOUBLE)
RETURN ROUND(coord, 2);   -- ~1.1 km, enough for regional analysis, not for locating a person

CREATE OR REPLACE FUNCTION IDENTIFIER(:catalog || '.' || :gold_schema || '.mask_address')(address STRING)
RETURN '[REDACTED]';

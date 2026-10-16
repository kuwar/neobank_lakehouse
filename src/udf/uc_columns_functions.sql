-- Column masks for the ABAC policies. Exempt groups are handled by the policy
-- (except_principals), so the functions only return the masked value.

-- Last 4 digits
CREATE OR REPLACE FUNCTION IDENTIFIER(:catalog || '.' || :gold_schema || '.mask_card_number')(card_number BIGINT)
RETURN CAST(RIGHT(CAST(card_number AS STRING), 4) AS BIGINT);

CREATE OR REPLACE FUNCTION IDENTIFIER(:catalog || '.' || :gold_schema || '.mask_cvv')(cvv INT)
RETURN CAST(NULL AS INT);

CREATE OR REPLACE FUNCTION IDENTIFIER(:catalog || '.' || :gold_schema || '.mask_coordinate')(coord DOUBLE)
RETURN ROUND(coord, 2);   -- ~1.1 km

CREATE OR REPLACE FUNCTION IDENTIFIER(:catalog || '.' || :gold_schema || '.mask_address')(address STRING)
RETURN '[REDACTED]';

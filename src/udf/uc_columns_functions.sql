-- Mask the card number
CREATE OR REPLACE FUNCTION IDENTIFIER(:catalog || '.' || :gold_schema || '.mask_card_number')(card_number BIGINT)
RETURN CASE
  WHEN is_account_group_member('pci_readers') THEN card_number
  ELSE CAST(RIGHT(CAST(card_number AS STRING), 4) AS BIGINT)
END;

CREATE OR REPLACE FUNCTION IDENTIFIER(:catalog || '.' || :gold_schema || '.mask_cvv')(cvv INT)
RETURN CASE 
  WHEN is_account_group_member('pci_readers') THEN cvv 
  ELSE NULL 
END;

CREATE OR REPLACE FUNCTION IDENTIFIER(:catalog || '.' || :gold_schema || '.mask_coordinate')(coord DOUBLE)
RETURN CASE
  WHEN is_account_group_member('pii_readers') THEN coord
  ELSE ROUND(coord, 2)   -- ~1.1 km, enough for regional analysis, not for locating a person
END;

CREATE OR REPLACE FUNCTION IDENTIFIER(:catalog || '.' || :gold_schema || '.mask_address')(address STRING)
RETURN CASE
  WHEN is_account_group_member('pii_readers') THEN address
  ELSE '[REDACTED]'
END;

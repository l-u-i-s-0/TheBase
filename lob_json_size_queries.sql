-- Ver la configuración actual del LOB
SELECT table_name, column_name, securefile, in_row, chunk,
       compression, deduplication, retention
FROM dba_lobs
WHERE table_name = 'SMARTPRICING_CUSTOMER_PRICES_U_TMP'
  AND column_name = 'PRECIO';

-- Tamaño medio real del JSON
SELECT AVG(LENGTH(PRECIO)), MAX(LENGTH(PRECIO)), MIN(LENGTH(PRECIO))
FROM EXHPRO.SMARTPRICING_CUSTOMER_PRICES_U_TMP;

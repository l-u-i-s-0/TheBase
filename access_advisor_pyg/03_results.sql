-- ============================================================
-- 03_results.sql  -  Consultar recomendaciones
-- ============================================================
-- Requiere haber ejecutado 02_advisor.sql en la misma sesion
-- (la variable &task_name debe estar definida).
--
-- Si abres una sesion nueva, define la variable antes:
--   DEFINE task_name = 'ACC_ADV_PYG'
-- ============================================================

PROMPT ==============================================
PROMPT  03_results  -  Recomendaciones del advisor
PROMPT  Task: &task_name
PROMPT ==============================================

-- ------------------------------------------------------------
-- 1. Resumen de recomendaciones (ordenadas por beneficio)
-- ------------------------------------------------------------
PROMPT
PROMPT --- 1. Resumen de recomendaciones ---

COLUMN rec_id        FORMAT 999         HEADING 'ID'
COLUMN benefit_type  FORMAT A15         HEADING 'Tipo'
COLUMN benefit_value FORMAT 99999999999 HEADING 'Beneficio'
COLUMN message       FORMAT A70 WRAP    HEADING 'Descripcion'

SELECT rec_id,
       benefit_type,
       benefit_value,
       message
FROM   user_advisor_recommendations
WHERE  task_name = '&task_name'
ORDER BY benefit_value DESC;


-- ------------------------------------------------------------
-- 2. Acciones detalladas (DDLs sugeridos)
-- ------------------------------------------------------------
PROMPT
PROMPT --- 2. Acciones recomendadas (DDLs) ---

COLUMN rec_id   FORMAT 999  HEADING 'REC'
COLUMN command  FORMAT A12  HEADING 'Comando'
COLUMN attr1    FORMAT A55 WRAP HEADING 'Objeto / DDL'
COLUMN attr2    FORMAT A20  HEADING 'Tablespace'
COLUMN attr3    FORMAT A10  HEADING 'Extra'

SELECT a.rec_id,
       a.command,
       a.attr1,
       a.attr2,
       a.attr3
FROM   user_advisor_actions a
WHERE  a.task_name = '&task_name'
ORDER BY a.rec_id;


-- ------------------------------------------------------------
-- 3. Script SQL completo listo para implementar
-- ------------------------------------------------------------
PROMPT
PROMPT --- 3. Script DDL completo ---

SET LONG 100000
SET LONGCHUNKSIZE 100000

SELECT DBMS_ADVISOR.GET_TASK_SCRIPT('&task_name') AS ddl_script
FROM   DUAL;


-- ------------------------------------------------------------
-- 4. Limpieza (descomentar cuando ya no se necesite)
-- ------------------------------------------------------------
-- EXEC DBMS_ADVISOR.DELETE_TASK('&task_name');
-- EXEC DBMS_ADVISOR.DELETE_SQLWKLD('&wkld_name');

-- ============================================================
-- 00_config.sql  -  Configuracion y nombres de objetos
-- ============================================================
-- Edita task_name y wkld_name si necesitas un sufijo distinto.
-- El sql_id corresponde a la sesion GUIA (SID 2297 / Serial# 33661).
--
-- Orden de ejecucion (misma sesion SQL*Plus):
--   @access_advisor_pyg/00_config.sql
--   @access_advisor_pyg/01_workload.sql
--   @access_advisor_pyg/02_advisor.sql
--   @access_advisor_pyg/03_results.sql
-- ============================================================

DEFINE sql_id    = '90zdv03f74mvb'
DEFINE task_name = 'ACC_ADV_PYG'
DEFINE wkld_name = 'WKL_PYG'

SET SERVEROUTPUT ON SIZE UNLIMITED
SET LONG          65536
SET LONGCHUNKSIZE 65536
SET LINESIZE      200
SET PAGESIZE      200
SET VERIFY        OFF

PROMPT ==============================================
PROMPT  00_config  -  Variables definidas
PROMPT ==============================================
PROMPT  sql_id    = &sql_id
PROMPT  task_name = &task_name
PROMPT  wkld_name = &wkld_name
PROMPT  Siguiente: @access_advisor_pyg/01_workload.sql
PROMPT ==============================================

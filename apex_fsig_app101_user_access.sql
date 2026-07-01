-- Extraccion de usuarios/perfiles para la aplicacion APEX "Upload e
-- Exploracao de Dados" (RITM020542823 / SCF PT CPT000041), workspace FSIG.
--
-- Valores confirmados en el entorno (Oracle 19c, APEX release nativo,
-- conectado con SYSDBA):
--   WORKSPACE = FSIG
--   APPLICATION_ID = 101 (alias F101)
--   PARSING_SCHEMA = ODS
--
-- El workspace FSIG tiene activo "Database Accounts": los usuarios de la
-- app se autentican contra cuentas nativas de Oracle, no contra usuarios
-- internos de APEX. Ver apex_app_users_profile_extraction.sql para el
-- runbook generico parametrizado.

-- =====================================================================
-- Confirmacion de la aplicacion (ya verificado)
-- =====================================================================
SELECT application_id, application_name, alias, owner AS parsing_schema, workspace
FROM   apex_applications
WHERE  workspace = 'FSIG'
ORDER BY application_id;

-- =====================================================================
-- Esquema de autenticacion: apex_application_authentication no existe
-- en esta version de APEX (ORA-00942). Localizar el nombre real de la
-- vista antes de reintentar la verificacion por esta via:
-- =====================================================================
SELECT view_name FROM dba_views WHERE view_name LIKE 'APEX%AUTH%' ORDER BY view_name;

-- =====================================================================
-- Usuarios de workspace registrados en APEX (admins/developers)
-- Esta lista la mantiene APEX aunque la autenticacion sea Database Accounts.
--
-- OJO: en esta version de APEX la columna LAST_ACCESS_DATE no existe
-- (ORA-00904). Verificar primero las columnas reales de la vista:
-- =====================================================================
SELECT column_name
FROM   dba_tab_columns
WHERE  table_name = 'APEX_WORKSPACE_APEX_USERS'
ORDER BY column_name;

-- Ajustar el SELECT con el nombre real de la columna de ultimo acceso
-- (ejemplo generico sin esa columna, siempre valido):
SELECT workspace_name, user_name, default_schema, account_type
FROM   apex_workspace_apex_users
WHERE  workspace_name = 'FSIG'
ORDER BY user_name;

-- =====================================================================
-- Cuentas de base de datos con privilegios sobre el schema real de la
-- aplicacion (ODS) -- universo de LOGIN ID con acceso a los datos
--
-- dba_tab_privs tiene una fila por (grantee, tabla, privilegio), por lo
-- que el conteo total puede ser muy alto (miles de filas) sin que eso
-- signifique miles de usuarios distintos. Agrupar por grantee:
-- =====================================================================

-- Lista distinta de grantees (usuarios o roles) con acceso a ODS
SELECT DISTINCT grantee
FROM   dba_tab_privs
WHERE  owner = 'ODS'
ORDER BY grantee;

-- Resumen: privilegios y cantidad de objetos por grantee
SELECT grantee, privilege, COUNT(*) AS objetos
FROM   dba_tab_privs
WHERE  owner = 'ODS'
GROUP BY grantee, privilege
ORDER BY grantee, privilege;

-- Si algun grantee es un ROL (no un usuario final), ver a quien se lo
-- otorgaron para llegar al LOGIN ID real:
SELECT grantee AS login_id
FROM   dba_role_privs
WHERE  granted_role = '&&ROLE_NAME';

-- =====================================================================
-- Cuentas de base de datos activas (candidatas a LOGIN ID real)
-- =====================================================================
SELECT username AS login_id, account_status, created, lock_date, comments
FROM   dba_users
WHERE  account_status = 'OPEN'
ORDER BY username;

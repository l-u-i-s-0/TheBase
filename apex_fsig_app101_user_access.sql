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
-- Esta lista la mantiene APEX aunque la autenticacion sea Database Accounts
-- =====================================================================
SELECT workspace_name, user_name, default_schema, account_type, last_access_date
FROM   apex_workspace_apex_users
WHERE  workspace_name = 'FSIG'
ORDER BY user_name;

-- =====================================================================
-- Cuentas de base de datos con privilegios sobre el schema real de la
-- aplicacion (ODS) -- universo de LOGIN ID con acceso a los datos
-- =====================================================================
SELECT grantee, privilege
FROM   dba_tab_privs
WHERE  owner = 'ODS'
ORDER BY grantee;

-- =====================================================================
-- Cuentas de base de datos activas (candidatas a LOGIN ID real)
-- =====================================================================
SELECT username AS login_id, account_status, created, lock_date, comments
FROM   dba_users
WHERE  account_status = 'OPEN'
ORDER BY username;

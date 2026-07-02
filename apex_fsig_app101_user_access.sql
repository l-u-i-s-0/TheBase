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
-- en esta version de APEX (ORA-00942). Vistas reales disponibles:
--   APEX_APPLICATION_ALL_AUTH, APEX_APPLICATION_AUTH,
--   APEX_APPLICATION_AUTHORIZATION
-- =====================================================================
SELECT view_name FROM dba_views WHERE view_name LIKE 'APEX%AUTH%' ORDER BY view_name;

-- Columnas reales de apex_application_auth (verificar antes de usarla)
SELECT LISTAGG(column_name, ', ') WITHIN GROUP (ORDER BY column_name) AS columnas
FROM   dba_tab_columns
WHERE  table_name = 'APEX_APPLICATION_AUTH';

-- =====================================================================
-- Usuarios de workspace registrados en APEX (admins/developers)
-- Esta lista la mantiene APEX aunque la autenticacion sea Database Accounts.
--
-- Columnas reales confirmadas en esta version (ORA-00904 en
-- LAST_ACCESS_DATE y ACCOUNT_TYPE, que NO existen aqui):
--   ACCOUNT_EXPIRY, ACCOUNT_LOCKED, AVAILABLE_SCHEMAS, DATE_CREATED,
--   DATE_LAST_UPDATED, DESCRIPTION, EMAIL, FAILED_ACCESS_ATTEMPTS,
--   FIRST_NAME, FIRST_SCHEMA_PROVISIONED, IS_ADMIN,
--   IS_APPLICATION_DEVELOPER, LAST_NAME, PASSWORD_VERSION,
--   PROFILE_CHARSET, PROFILE_FILENAME, PROFILE_IMAGE_NAME,
--   PROFILE_MIMETYPE, USER_NAME, WORKSPACE_DISPLAY_NAME,
--   WORKSPACE_ID, WORKSPACE_NAME
--
-- FIRST_NAME/LAST_NAME/EMAIL cubren el FULLNAME pedido en el ticket, e
-- IS_ADMIN / IS_APPLICATION_DEVELOPER hacen de PROFILE. Confirmar antes
-- el literal real de esas dos columnas (se asume 'Yes'/'No'):
-- =====================================================================
SELECT DISTINCT is_admin, is_application_developer
FROM   apex_workspace_apex_users;

SELECT user_name                             AS login_id,
       TRIM(first_name || ' ' || last_name)  AS fullname,
       email,
       CASE WHEN is_admin = 'Yes'                THEN 'Workspace Administrator'
            WHEN is_application_developer = 'Yes' THEN 'Developer'
            ELSE 'End User'
       END                                   AS profile,
       available_schemas,
       account_locked,
       date_created,
       date_last_updated
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

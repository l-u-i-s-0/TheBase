-- =============================================================================
-- 01_pre_extraccion.sql
-- PASO 1 DE 3 — Ejecutar en PRE como SYSDBA
-- Audita el esquema y genera todos los ficheros necesarios para DEV.
--
-- USO:
--   sqlplus / as sysdba          (local)
--   sqlplus /@PRE as sysdba      (remota)
--   SQL> DEFINE v_schema = 'MI_ESQUEMA'
--   SQL> @01_pre_extraccion.sql
--
-- NOTA SOBRE TABLESPACES:
--   Los DDL incluyen el tablespace real donde reside cada objeto en PRE (TABLESPACE=TRUE).
--   Si el tablespace no existe en DEV, la creación del objeto fallará.
--   El script dev_01_usuario_grants.sql incluye una sección [A-TABLESPACES] con la lista
--   de tablespaces necesarios y las sentencias de cuota para el usuario.
--   Si un tablespace de PRE no existe en DEV, créalo antes o edita el DDL para
--   redirigir ese objeto a otro tablespace disponible.
--   El bloque STORAGE (tamaños iniciales, extents) se elimina para evitar problemas
--   de espacio físico; Oracle usará los valores por defecto del tablespace destino.
--
-- FICHEROS GENERADOS:
--   pre_informe_NLS.txt          Comparativa NLS — revisar ANTES de continuar
--   pre_informe_auditoria.txt    Informe completo de permisos, estado y tablespaces
--   dev_01_usuario_grants.sql    Tablespaces necesarios, usuario, cuotas, privilegios, roles
--   dev_02_ddl_objetos.sql       DDL de todos los objetos (tablespace real, sin STORAGE)
--   dev_03_pre_carga.sql         Deshabilitar triggers y jobs antes de cargar
--   dev_04_post_carga.sql        Rehabilitar, reajustar secuencias, recompilar
--   dev_05_validacion.sql        Validación final tras la carga
-- =============================================================================

DEFINE v_schema = 'NOMBRE_ESQUEMA'   -- <<<< UNICO PARAMETRO A CAMBIAR

-- Derivados (no tocar)
DEFINE f_nls         = 'pre_informe_NLS.txt'
DEFINE f_auditoria   = 'pre_informe_auditoria.txt'
DEFINE f_grants      = 'dev_01_usuario_grants.sql'
DEFINE f_ddl         = 'dev_02_ddl_objetos.sql'
DEFINE f_precarga    = 'dev_03_pre_carga.sql'
DEFINE f_postcarga   = 'dev_04_post_carga.sql'
DEFINE f_validacion  = 'dev_05_validacion.sql'

SET SERVEROUTPUT ON SIZE UNLIMITED
SET LONG        2000000
SET LONGCHUNKSIZE 32767
SET LINESIZE    200
SET TRIMSPOOL   ON
SET FEEDBACK    OFF
SET VERIFY      OFF
SET HEADING     ON
SET PAGESIZE    50
SET ECHO        OFF

PROMPT
PROMPT ============================================================
PROMPT  EXTRACCION PRE -> DEV  |  Esquema: &v_schema
SELECT ' Fecha: ' || TO_CHAR(SYSDATE,'DD/MM/YYYY HH24:MI:SS') FROM DUAL;
PROMPT ============================================================
PROMPT


-- ============================================================================
-- FICHERO 1: INFORME NLS  (revisar antes de cualquier otra cosa)
-- ============================================================================
SPOOL &f_nls
PROMPT ============================================================
PROMPT  PARAMETROS NLS - PRE
PROMPT  Comparar con DEV antes de continuar la migración
PROMPT ============================================================
SELECT parameter, value
FROM   nls_database_parameters
WHERE  parameter IN (
    'NLS_CHARACTERSET','NLS_NCHAR_CHARACTERSET',
    'NLS_DATE_FORMAT','NLS_DATE_LANGUAGE',
    'NLS_NUMERIC_CHARACTERS','NLS_LENGTH_SEMANTICS',
    'NLS_TERRITORY','NLS_LANGUAGE'
)
ORDER BY parameter;

PROMPT
PROMPT *** ACCION REQUERIDA: ejecutar esta misma query en DEV y comparar.
PROMPT *** Si NLS_CHARACTERSET difiere -> PARAR. Es un cambio de instancia.
PROMPT *** Si NLS_DATE_FORMAT difiere  -> ajustar formato en la carga de datos.
SPOOL OFF
PROMPT [OK] Generado: &f_nls


-- ============================================================================
-- FICHERO 2: INFORME DE AUDITORIA COMPLETA
-- ============================================================================
SPOOL &f_auditoria

PROMPT ============================================================
PROMPT  INFORME DE AUDITORIA - ESQUEMA: &v_schema
SELECT ' Fecha: ' || TO_CHAR(SYSDATE,'DD/MM/YYYY HH24:MI:SS') FROM DUAL;
PROMPT ============================================================

PROMPT
PROMPT --- [1] DEFINICION DEL USUARIO ------------------------------------
SELECT username, account_status, default_tablespace,
       temporary_tablespace, profile, created
FROM   dba_users WHERE username = UPPER('&v_schema');

PROMPT
PROMPT --- [2] CUOTAS DE TABLESPACE (sin cuota = ORA-01536 en INSERT) ---
SELECT tablespace_name,
       CASE WHEN max_bytes=-1 THEN 'UNLIMITED'
            ELSE TO_CHAR(ROUND(max_bytes/1048576,2))||' MB' END cuota_max,
       ROUND(bytes/1048576,2)||' MB' usado
FROM   dba_ts_quotas WHERE username = UPPER('&v_schema') ORDER BY 1;

PROMPT
PROMPT --- [3] PRIVILEGIOS DE SISTEMA ------------------------------------
SELECT privilege, admin_option FROM dba_sys_privs
WHERE  grantee = UPPER('&v_schema') ORDER BY 1;

PROMPT
PROMPT --- [4] ROLES CONCEDIDOS ------------------------------------------
SELECT granted_role, admin_option, default_role FROM dba_role_privs
WHERE  grantee = UPPER('&v_schema') ORDER BY 1;

PROMPT
PROMPT --- [5] GRANTS RECIBIDOS DE OTROS ESQUEMAS -----------------------
SELECT owner AS esquema_origen, table_name AS objeto,
       privilege, grantable FROM dba_tab_privs
WHERE  grantee = UPPER('&v_schema') AND owner != UPPER('&v_schema')
ORDER BY 1,2,3;

PROMPT
PROMPT --- [6] GRANTS OTORGADOS A OTROS ----------------------------------
SELECT grantee, table_name AS objeto, privilege, grantable FROM dba_tab_privs
WHERE  owner = UPPER('&v_schema') AND grantee != UPPER('&v_schema')
ORDER BY 1,2,3;

PROMPT
PROMPT --- [7] SINONIMOS PUBLICOS que apuntan a este esquema -------------
SELECT synonym_name, table_name, db_link FROM dba_synonyms
WHERE  owner='PUBLIC' AND table_owner=UPPER('&v_schema') ORDER BY 1;

PROMPT
PROMPT --- [8] SINONIMOS PRIVADOS hacia objetos EXTERNOS ----------------
SELECT synonym_name, table_owner AS destino, table_name, db_link
FROM   dba_synonyms
WHERE  owner=UPPER('&v_schema') AND table_owner!=UPPER('&v_schema') ORDER BY 2,1;

PROMPT
PROMPT --- [9] DATABASE LINKS -------------------------------------------
SELECT db_link, username, host FROM dba_db_links
WHERE  owner=UPPER('&v_schema') ORDER BY 1;

PROMPT
PROMPT --- [10] PERFIL DEL USUARIO (limites que pueden cortar la carga) -
SELECT p.resource_name, p.limit FROM dba_profiles p
JOIN   dba_users u ON u.profile=p.profile
WHERE  u.username=UPPER('&v_schema')
AND    p.resource_name IN ('SESSIONS_PER_USER','IDLE_TIME','CONNECT_TIME',
       'CPU_PER_SESSION','LOGICAL_READS_PER_SESSION',
       'PASSWORD_LIFE_TIME','FAILED_LOGIN_ATTEMPTS')
ORDER BY 1;

PROMPT
PROMPT --- [11] OBJETOS INVALIDOS en PRE (resolver ANTES de migrar) -----
SELECT object_type, object_name, status, last_ddl_time FROM dba_objects
WHERE  owner=UPPER('&v_schema') AND status='INVALID' ORDER BY 1,2;

PROMPT
PROMPT --- [12] TRIGGERS HABILITADOS ------------------------------------
SELECT trigger_name, table_name, trigger_type, triggering_event, status
FROM   dba_triggers WHERE owner=UPPER('&v_schema') AND status='ENABLED'
ORDER BY 2,1;

PROMPT
PROMPT --- [13] JOBS DEL SCHEDULER --------------------------------------
SELECT job_name, enabled, state, repeat_interval, last_run_date
FROM   dba_scheduler_jobs WHERE owner=UPPER('&v_schema') ORDER BY 1;

PROMPT
PROMPT --- [14] DBMS_JOB (legacy) ---------------------------------------
SELECT job, what, next_date, broken FROM dba_jobs
WHERE  schema_user=UPPER('&v_schema') ORDER BY 1;

PROMPT
PROMPT --- [15] ACLs DE RED (UTL_HTTP / UTL_SMTP) ----------------------
BEGIN
  -- Oracle 12c+
  FOR r IN (SELECT host, lower_port, upper_port, principal, privilege, is_grant
            FROM dba_host_aces WHERE principal=UPPER('&v_schema')) LOOP
    DBMS_OUTPUT.PUT_LINE(r.host||':'||r.lower_port||'-'||r.upper_port
                         ||' '||r.privilege||' grant='||r.is_grant);
  END LOOP;
EXCEPTION WHEN OTHERS THEN
  -- Oracle 11g fallback
  FOR r IN (SELECT a.acl, a.host, p.principal, p.privilege, p.is_grant
            FROM dba_network_acls a JOIN dba_network_acl_privileges p ON a.acl=p.acl
            WHERE p.principal=UPPER('&v_schema')) LOOP
    DBMS_OUTPUT.PUT_LINE(r.host||' '||r.privilege||' grant='||r.is_grant);
  END LOOP;
END;
/

PROMPT
PROMPT --- [16] SECUENCIAS (valor actual — reajustar tras la carga) -----
SELECT sequence_name, last_number, min_value, max_value,
       increment_by, cycle_flag, order_flag, cache_size
FROM   dba_sequences WHERE sequence_owner=UPPER('&v_schema') ORDER BY 1;

PROMPT
PROMPT --- [17] DIRECTORY OBJECTS con acceso desde este esquema ---------
SELECT d.directory_name, d.directory_path, tp.privilege
FROM   dba_tab_privs tp JOIN dba_directories d ON d.directory_name=tp.table_name
WHERE  tp.grantee=UPPER('&v_schema') ORDER BY 1;

PROMPT
PROMPT --- [18] TABLESPACES USADOS POR OBJETOS DEL ESQUEMA EN PRE ------
PROMPT --     El DDL se genera SIN tablespace (SEGMENT_ATTRIBUTES=FALSE)
PROMPT --     Los objetos iran al tablespace por defecto del usuario en DEV.
PROMPT --     Asegurate de que ese tablespace tenga cuota suficiente.
PROMPT --     Si necesitas que objetos concretos vayan a otro tablespace,
PROMPT --     edita manualmente el DDL generado o usa ALTER INDEX ... REBUILD.
PROMPT
SELECT segment_type AS tipo,
       tablespace_name,
       COUNT(*)           AS num_objetos,
       ROUND(SUM(bytes)/1048576,1) AS mb_usado
FROM   dba_segments
WHERE  owner = UPPER('&v_schema')
GROUP BY segment_type, tablespace_name
ORDER BY segment_type, tablespace_name;

PROMPT
PROMPT --- [19] RESUMEN DE OBJETOS POR TIPO ----------------------------
SELECT object_type,
       COUNT(*) total,
       SUM(CASE WHEN status='VALID'   THEN 1 ELSE 0 END) validos,
       SUM(CASE WHEN status='INVALID' THEN 1 ELSE 0 END) invalidos
FROM   dba_objects WHERE owner=UPPER('&v_schema')
GROUP BY object_type ORDER BY 1;

SPOOL OFF
PROMPT [OK] Generado: &f_auditoria


-- ============================================================================
-- Configurar DBMS_METADATA:
--   SEGMENT_ATTRIBUTES=TRUE  -> conserva TABLESPACE real de cada objeto
--   STORAGE=FALSE            -> elimina el bloque STORAGE (tamaños físicos)
--   TABLESPACE=TRUE          -> incluye cláusula TABLESPACE en el DDL
-- Así cada objeto se crea en el mismo tablespace que tiene en PRE.
-- Si ese tablespace no existe en DEV, el script dev_01_usuario_grants.sql
-- incluye las sentencias necesarias para crearlo o redirigirlo.
-- ============================================================================
BEGIN
    DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM,'SEGMENT_ATTRIBUTES',TRUE);
    DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM,'STORAGE',           FALSE);
    DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM,'TABLESPACE',        TRUE);
    DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM,'SQLTERMINATOR',     TRUE);
    DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM,'PRETTY',            TRUE);
    DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM,'REF_CONSTRAINTS',   FALSE);
    DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM,'CONSTRAINTS',       FALSE);
END;
/

SET HEADING   OFF
SET PAGESIZE  0


-- ============================================================================
-- FICHERO 3: USUARIO + GRANTS + CUOTAS + ROLES + SINONIMOS PUBLICOS
-- ============================================================================
SPOOL &f_grants
PROMPT -- ==================================================================
PROMPT -- dev_01_usuario_grants.sql — Ejecutar en DEV como SYSDBA
SELECT '-- Generado desde PRE el ' || TO_CHAR(SYSDATE,'DD/MM/YYYY HH24:MI:SS') FROM DUAL;
PROMPT -- PASO 1: ajustar contraseña en la linea CREATE USER antes de ejecutar
PROMPT -- ==================================================================
PROMPT

PROMPT -- [A] TABLESPACES REQUERIDOS EN DEV
PROMPT --     Los DDL de los objetos incluyen el tablespace real de PRE.
PROMPT --     Ejecutar primero en DEV: SELECT tablespace_name FROM dba_tablespaces;
PROMPT --     Si alguno de los siguientes no existe en DEV, crearlo o editar el DDL.
PROMPT --     Las sentencias de cuota se generan con UNLIMITED; ajustar si es necesario.
PROMPT
DECLARE
  v_owner VARCHAR2(128) := UPPER('&v_schema');
BEGIN
  -- Tablespaces de segmentos (tablas, índices, lobs)
  FOR t IN (
    SELECT DISTINCT tablespace_name
    FROM   dba_segments
    WHERE  owner = v_owner
      AND  tablespace_name IS NOT NULL
    UNION
    -- Tablespace por defecto y temporal del usuario
    SELECT default_tablespace   FROM dba_users WHERE username = v_owner
    UNION
    SELECT temporary_tablespace FROM dba_users WHERE username = v_owner
    ORDER BY 1
  ) LOOP
    DBMS_OUTPUT.PUT_LINE('-- Verificar en DEV: SELECT count(*) FROM dba_tablespaces WHERE tablespace_name='''||t.tablespace_name||''';');
    DBMS_OUTPUT.PUT_LINE('ALTER USER "'||v_owner||'" QUOTA UNLIMITED ON "'||t.tablespace_name||'";');
    DBMS_OUTPUT.PUT_LINE('');
  END LOOP;
END;
/
PROMPT

PROMPT -- [B] USUARIO
PROMPT --     Ajustar la contrasena antes de ejecutar.
PROMPT --     DEFAULT TABLESPACE tomado de PRE; cambiarlo si el nombre difiere en DEV.
PROMPT
SELECT 'CREATE USER "' || username || '"'
    || ' IDENTIFIED BY "CAMBIAR_PASSWORD_AQUI"'
    || ' DEFAULT TABLESPACE "' || default_tablespace || '"'
    || ' TEMPORARY TABLESPACE "' || temporary_tablespace || '"'
    || ' PROFILE "' || profile || '";'
FROM   dba_users WHERE username=UPPER('&v_schema');
PROMPT
SELECT 'ALTER USER "' || username || '" ACCOUNT UNLOCK;'
FROM   dba_users WHERE username=UPPER('&v_schema');
PROMPT

PROMPT -- [C] CUOTAS ADICIONALES (las de los tablespaces de objetos ya estan en [A])
PROMPT
SELECT 'ALTER USER "' || username || '" QUOTA '
    || CASE WHEN max_bytes=-1 THEN 'UNLIMITED' ELSE TO_CHAR(ROUND(max_bytes/1048576))||'M' END
    || ' ON "' || tablespace_name || '";'
FROM   dba_ts_quotas WHERE username=UPPER('&v_schema') ORDER BY 2;
PROMPT

PROMPT -- [D] PRIVILEGIOS DE SISTEMA
PROMPT
SELECT 'GRANT ' || privilege
    || CASE WHEN admin_option='YES' THEN ' WITH ADMIN OPTION' ELSE '' END
    || ' TO "' || grantee || '";'
FROM   dba_sys_privs WHERE grantee=UPPER('&v_schema') ORDER BY 1;
PROMPT

PROMPT -- [E] ROLES
PROMPT
SELECT 'GRANT "' || granted_role || '"'
    || CASE WHEN admin_option='YES' THEN ' WITH ADMIN OPTION' ELSE '' END
    || ' TO "' || grantee || '";'
FROM   dba_role_privs WHERE grantee=UPPER('&v_schema') ORDER BY 1;
PROMPT

PROMPT -- [F] GRANTS RECIBIDOS DE OTROS ESQUEMAS
PROMPT --     Verificar que esos esquemas y objetos existen en DEV
PROMPT
SELECT 'GRANT ' || privilege
    || ' ON "' || owner || '"."' || table_name || '"'
    || ' TO "' || grantee || '"'
    || CASE WHEN grantable='YES' THEN ' WITH GRANT OPTION' ELSE '' END || ';'
FROM   dba_tab_privs
WHERE  grantee=UPPER('&v_schema') AND owner!=UPPER('&v_schema')
ORDER BY 1,2,3;
PROMPT

PROMPT -- [G] GRANTS OTORGADOS A OTROS USUARIOS/ROLES
PROMPT
SELECT 'GRANT ' || privilege
    || ' ON "' || owner || '"."' || table_name || '"'
    || ' TO "' || grantee || '"'
    || CASE WHEN grantable='YES' THEN ' WITH GRANT OPTION' ELSE '' END || ';'
FROM   dba_tab_privs
WHERE  owner=UPPER('&v_schema') AND grantee!=UPPER('&v_schema')
ORDER BY 1,2,3;
PROMPT

PROMPT -- [H] SINONIMOS PUBLICOS
PROMPT
SELECT 'CREATE OR REPLACE PUBLIC SYNONYM "' || synonym_name || '"'
    || ' FOR "' || table_owner || '"."' || table_name || '"'
    || CASE WHEN db_link IS NOT NULL THEN '@"'||db_link||'"' ELSE '' END || ';'
FROM   dba_synonyms
WHERE  owner='PUBLIC' AND table_owner=UPPER('&v_schema') ORDER BY 1;
PROMPT

PROMPT -- [I] ACLs DE RED (Oracle 12c+)
PROMPT --     Verificar hosts accesibles desde DEV antes de habilitar
PROMPT
BEGIN
  FOR r IN (
    SELECT DISTINCT host, lower_port, upper_port, principal, privilege, is_grant
    FROM   dba_host_aces WHERE principal=UPPER('&v_schema')
  ) LOOP
    IF r.is_grant = 'TRUE' THEN
      DBMS_OUTPUT.PUT_LINE(
        'BEGIN DBMS_NETWORK_ACL_ADMIN.APPEND_HOST_ACE('
        ||' host=>'''||r.host||''''
        ||CASE WHEN r.lower_port IS NOT NULL THEN ',lower_port=>'||r.lower_port ELSE '' END
        ||CASE WHEN r.upper_port IS NOT NULL THEN ',upper_port=>'||r.upper_port ELSE '' END
        ||', ace=>xs$ace_type(privilege_list=>xs$privilege_list('''||r.privilege||''')'
        ||', principal_name=>'''||r.principal||''',principal_type=>xs_acl.ptype_db)); END;'
        ||CHR(10)||'/'
      );
    END IF;
  END LOOP;
EXCEPTION WHEN OTHERS THEN
  DBMS_OUTPUT.PUT_LINE('-- ACLs no disponibles en esta version de Oracle (11g): revisar dba_network_acls');
END;
/
PROMPT

SPOOL OFF
PROMPT [OK] Generado: &f_grants


-- ============================================================================
-- FICHERO 4: DDL DE TODOS LOS OBJETOS
-- ============================================================================
SPOOL &f_ddl
PROMPT -- ==================================================================
PROMPT -- dev_02_ddl_objetos.sql — Ejecutar en DEV como SYSDBA
SELECT '-- Generado desde PRE el ' || TO_CHAR(SYSDATE,'DD/MM/YYYY HH24:MI:SS') FROM DUAL;
PROMPT -- Ejecutar DESPUES de dev_01_usuario_grants.sql
PROMPT -- ==================================================================
PROMPT

-- Tipos y cuerpos de tipo
DECLARE
  v_ddl CLOB; v_owner VARCHAR2(128):=UPPER('&v_schema');
BEGIN
  DBMS_OUTPUT.PUT_LINE('-- === TYPES ==='); DBMS_OUTPUT.PUT_LINE('');
  FOR r IN (SELECT object_type,object_name FROM dba_objects
            WHERE owner=v_owner AND object_type IN ('TYPE','TYPE BODY') AND status='VALID'
            AND object_name NOT LIKE 'SYS_PLSQL_%'
            ORDER BY CASE object_type WHEN 'TYPE' THEN 1 ELSE 2 END, object_name) LOOP
    BEGIN
      v_ddl:=DBMS_METADATA.GET_DDL(REPLACE(r.object_type,' ','_'),r.object_name,v_owner);
      DBMS_OUTPUT.PUT_LINE(v_ddl); DBMS_OUTPUT.PUT_LINE('/'); DBMS_OUTPUT.PUT_LINE('');
    EXCEPTION WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('-- ERROR '||r.object_type||' '||r.object_name||': '||SQLERRM);
    END;
  END LOOP;
END;
/

-- Sequences
DECLARE
  v_ddl CLOB; v_owner VARCHAR2(128):=UPPER('&v_schema');
BEGIN
  DBMS_OUTPUT.PUT_LINE('-- === SEQUENCES ==='); DBMS_OUTPUT.PUT_LINE('');
  FOR r IN (SELECT object_name FROM dba_objects
            WHERE owner=v_owner AND object_type='SEQUENCE' AND status='VALID'
            ORDER BY object_name) LOOP
    BEGIN
      v_ddl:=DBMS_METADATA.GET_DDL('SEQUENCE',r.object_name,v_owner);
      DBMS_OUTPUT.PUT_LINE(v_ddl); DBMS_OUTPUT.PUT_LINE('/'); DBMS_OUTPUT.PUT_LINE('');
    EXCEPTION WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('-- ERROR SEQUENCE '||r.object_name||': '||SQLERRM);
    END;
  END LOOP;
END;
/

-- Tables
DECLARE
  v_ddl CLOB; v_owner VARCHAR2(128):=UPPER('&v_schema');
BEGIN
  DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM,'CONSTRAINTS',FALSE);
  DBMS_OUTPUT.PUT_LINE('-- === TABLES ==='); DBMS_OUTPUT.PUT_LINE('');
  FOR r IN (SELECT object_name FROM dba_objects
            WHERE owner=v_owner AND object_type='TABLE' AND status='VALID'
            AND object_name NOT LIKE 'BIN$%' ORDER BY object_name) LOOP
    BEGIN
      v_ddl:=DBMS_METADATA.GET_DDL('TABLE',r.object_name,v_owner);
      DBMS_OUTPUT.PUT_LINE(v_ddl); DBMS_OUTPUT.PUT_LINE('/'); DBMS_OUTPUT.PUT_LINE('');
    EXCEPTION WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('-- ERROR TABLE '||r.object_name||': '||SQLERRM);
    END;
  END LOOP;
END;
/

-- Indexes (excluye los de PK/UK que se crean con la constraint)
DECLARE
  v_ddl CLOB; v_owner VARCHAR2(128):=UPPER('&v_schema');
BEGIN
  DBMS_OUTPUT.PUT_LINE('-- === INDEXES ==='); DBMS_OUTPUT.PUT_LINE('');
  FOR r IN (SELECT i.index_name FROM dba_indexes i
            WHERE i.owner=v_owner AND i.index_name NOT LIKE 'BIN$%'
            AND NOT EXISTS (SELECT 1 FROM dba_constraints c
                            WHERE c.owner=v_owner AND c.index_name=i.index_name
                            AND c.constraint_type IN ('P','U'))
            ORDER BY i.index_name) LOOP
    BEGIN
      v_ddl:=DBMS_METADATA.GET_DDL('INDEX',r.index_name,v_owner);
      DBMS_OUTPUT.PUT_LINE(v_ddl); DBMS_OUTPUT.PUT_LINE('/'); DBMS_OUTPUT.PUT_LINE('');
    EXCEPTION WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('-- ERROR INDEX '||r.index_name||': '||SQLERRM);
    END;
  END LOOP;
END;
/

-- PK y UK
DECLARE
  v_ddl CLOB; v_owner VARCHAR2(128):=UPPER('&v_schema');
BEGIN
  DBMS_OUTPUT.PUT_LINE('-- === PRIMARY KEYS / UNIQUE CONSTRAINTS ==='); DBMS_OUTPUT.PUT_LINE('');
  FOR r IN (SELECT constraint_name FROM dba_constraints
            WHERE owner=v_owner AND constraint_type IN ('P','U') AND status='ENABLED'
            ORDER BY table_name, constraint_name) LOOP
    BEGIN
      v_ddl:=DBMS_METADATA.GET_DDL('CONSTRAINT',r.constraint_name,v_owner);
      DBMS_OUTPUT.PUT_LINE(v_ddl); DBMS_OUTPUT.PUT_LINE('/'); DBMS_OUTPUT.PUT_LINE('');
    EXCEPTION WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('-- ERROR PK/UK '||r.constraint_name||': '||SQLERRM);
    END;
  END LOOP;
END;
/

-- Check constraints
DECLARE
  v_ddl CLOB; v_owner VARCHAR2(128):=UPPER('&v_schema');
BEGIN
  DBMS_OUTPUT.PUT_LINE('-- === CHECK CONSTRAINTS ==='); DBMS_OUTPUT.PUT_LINE('');
  FOR r IN (SELECT constraint_name FROM dba_constraints
            WHERE owner=v_owner AND constraint_type='C' AND status='ENABLED'
            AND generated='USER NAME' ORDER BY table_name, constraint_name) LOOP
    BEGIN
      v_ddl:=DBMS_METADATA.GET_DDL('CONSTRAINT',r.constraint_name,v_owner);
      DBMS_OUTPUT.PUT_LINE(v_ddl); DBMS_OUTPUT.PUT_LINE('/'); DBMS_OUTPUT.PUT_LINE('');
    EXCEPTION WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('-- ERROR CHECK '||r.constraint_name||': '||SQLERRM);
    END;
  END LOOP;
END;
/

-- Foreign Keys (al final para evitar dependencias de orden)
DECLARE
  v_ddl CLOB; v_owner VARCHAR2(128):=UPPER('&v_schema');
BEGIN
  DBMS_OUTPUT.PUT_LINE('-- === FOREIGN KEYS ==='); DBMS_OUTPUT.PUT_LINE('');
  FOR r IN (SELECT constraint_name FROM dba_constraints
            WHERE owner=v_owner AND constraint_type='R' AND status='ENABLED'
            ORDER BY table_name, constraint_name) LOOP
    BEGIN
      v_ddl:=DBMS_METADATA.GET_DDL('REF_CONSTRAINT',r.constraint_name,v_owner);
      DBMS_OUTPUT.PUT_LINE(v_ddl); DBMS_OUTPUT.PUT_LINE('/'); DBMS_OUTPUT.PUT_LINE('');
    EXCEPTION WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('-- ERROR FK '||r.constraint_name||': '||SQLERRM);
    END;
  END LOOP;
END;
/

-- Views
DECLARE
  v_ddl CLOB; v_owner VARCHAR2(128):=UPPER('&v_schema');
BEGIN
  DBMS_OUTPUT.PUT_LINE('-- === VIEWS ==='); DBMS_OUTPUT.PUT_LINE('');
  FOR r IN (SELECT object_name FROM dba_objects
            WHERE owner=v_owner AND object_type='VIEW' AND status='VALID'
            ORDER BY object_name) LOOP
    BEGIN
      v_ddl:=DBMS_METADATA.GET_DDL('VIEW',r.object_name,v_owner);
      DBMS_OUTPUT.PUT_LINE(v_ddl); DBMS_OUTPUT.PUT_LINE('/'); DBMS_OUTPUT.PUT_LINE('');
    EXCEPTION WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('-- ERROR VIEW '||r.object_name||': '||SQLERRM);
    END;
  END LOOP;
END;
/

-- Stored code
DECLARE
  v_ddl CLOB; v_owner VARCHAR2(128):=UPPER('&v_schema');
BEGIN
  DBMS_OUTPUT.PUT_LINE('-- === STORED CODE (PROCEDURES / FUNCTIONS / PACKAGES / TRIGGERS) ===');
  DBMS_OUTPUT.PUT_LINE('');
  FOR r IN (SELECT object_type, object_name FROM dba_objects
            WHERE owner=v_owner AND status='VALID'
            AND object_type IN ('PROCEDURE','FUNCTION','PACKAGE','PACKAGE BODY','TRIGGER')
            ORDER BY CASE object_type
              WHEN 'PACKAGE'      THEN 1 WHEN 'PACKAGE BODY' THEN 2
              WHEN 'PROCEDURE'    THEN 3 WHEN 'FUNCTION'     THEN 4
              WHEN 'TRIGGER'      THEN 5 ELSE 6 END, object_name) LOOP
    BEGIN
      v_ddl:=DBMS_METADATA.GET_DDL(REPLACE(r.object_type,' ','_'),r.object_name,v_owner);
      DBMS_OUTPUT.PUT_LINE(v_ddl); DBMS_OUTPUT.PUT_LINE('/'); DBMS_OUTPUT.PUT_LINE('');
    EXCEPTION WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('-- ERROR '||r.object_type||' '||r.object_name||': '||SQLERRM);
    END;
  END LOOP;
END;
/

-- Synonyms
DECLARE
  v_ddl CLOB; v_owner VARCHAR2(128):=UPPER('&v_schema');
BEGIN
  DBMS_OUTPUT.PUT_LINE('-- === SYNONYMS ==='); DBMS_OUTPUT.PUT_LINE('');
  FOR r IN (SELECT object_name FROM dba_objects
            WHERE owner=v_owner AND object_type='SYNONYM' AND status='VALID'
            ORDER BY object_name) LOOP
    BEGIN
      v_ddl:=DBMS_METADATA.GET_DDL('SYNONYM',r.object_name,v_owner);
      DBMS_OUTPUT.PUT_LINE(v_ddl); DBMS_OUTPUT.PUT_LINE('/'); DBMS_OUTPUT.PUT_LINE('');
    EXCEPTION WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('-- ERROR SYNONYM '||r.object_name||': '||SQLERRM);
    END;
  END LOOP;
END;
/

-- DB Links
DECLARE
  v_ddl CLOB; v_owner VARCHAR2(128):=UPPER('&v_schema');
BEGIN
  DBMS_OUTPUT.PUT_LINE('-- === DATABASE LINKS ==='); DBMS_OUTPUT.PUT_LINE('');
  FOR r IN (SELECT object_name FROM dba_objects
            WHERE owner=v_owner AND object_type='DATABASE LINK'
            ORDER BY object_name) LOOP
    BEGIN
      v_ddl:=DBMS_METADATA.GET_DDL('DB_LINK',r.object_name,v_owner);
      DBMS_OUTPUT.PUT_LINE(v_ddl); DBMS_OUTPUT.PUT_LINE('/'); DBMS_OUTPUT.PUT_LINE('');
    EXCEPTION WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('-- ERROR DB_LINK '||r.object_name||': '||SQLERRM);
    END;
  END LOOP;
END;
/

-- Object grants
DECLARE
  v_ddl CLOB; v_owner VARCHAR2(128):=UPPER('&v_schema');
BEGIN
  DBMS_OUTPUT.PUT_LINE('-- === OBJECT GRANTS ==='); DBMS_OUTPUT.PUT_LINE('');
  FOR r IN (SELECT DISTINCT object_name, object_type FROM dba_objects
            WHERE owner=v_owner AND status='VALID'
            AND object_type IN ('TABLE','VIEW','SEQUENCE','PROCEDURE','FUNCTION','PACKAGE','TYPE')
            ORDER BY object_type, object_name) LOOP
    BEGIN
      v_ddl:=DBMS_METADATA.GET_DEPENDENT_DDL('OBJECT_GRANT',r.object_name,v_owner);
      IF v_ddl IS NOT NULL THEN
        DBMS_OUTPUT.PUT_LINE(v_ddl); DBMS_OUTPUT.PUT_LINE('/'); DBMS_OUTPUT.PUT_LINE('');
      END IF;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END LOOP;
END;
/

SPOOL OFF
PROMPT [OK] Generado: &f_ddl


-- ============================================================================
-- FICHERO 5: PRE-CARGA (deshabilitar triggers, jobs, constraints FK)
-- ============================================================================
SPOOL &f_precarga
PROMPT -- ==================================================================
PROMPT -- dev_03_pre_carga.sql — Ejecutar en DEV como SYSDBA antes de cargar
SELECT '-- Generado desde PRE el ' || TO_CHAR(SYSDATE,'DD/MM/YYYY HH24:MI:SS') FROM DUAL;
PROMPT -- ==================================================================
PROMPT

PROMPT -- [A] DESHABILITAR FOREIGN KEYS (evitar errores de integridad durante carga)
PROMPT
SELECT 'ALTER TABLE "'||UPPER('&v_schema')||'"."'||table_name
    ||'" DISABLE CONSTRAINT "'||constraint_name||'";'
FROM   dba_constraints
WHERE  owner=UPPER('&v_schema') AND constraint_type='R'
ORDER BY table_name, constraint_name;
PROMPT

PROMPT -- [B] DESHABILITAR TRIGGERS
PROMPT
SELECT 'ALTER TRIGGER "'||UPPER('&v_schema')||'"."'||trigger_name||'" DISABLE;'
FROM   dba_triggers WHERE owner=UPPER('&v_schema') ORDER BY trigger_name;
PROMPT

PROMPT -- [C] DESHABILITAR JOBS DEL SCHEDULER
PROMPT
SELECT 'BEGIN DBMS_SCHEDULER.DISABLE(''"'||UPPER('&v_schema')||'"."'||job_name||'"''); END;'
    ||CHR(10)||'/'
FROM   dba_scheduler_jobs WHERE owner=UPPER('&v_schema') AND enabled='TRUE' ORDER BY job_name;
PROMPT

PROMPT -- [D] DESHABILITAR DBMS_JOB (legacy) — marcarlos como BROKEN
PROMPT
SELECT 'BEGIN DBMS_JOB.BROKEN('||job||',TRUE); COMMIT; END;'||CHR(10)||'/'
FROM   dba_jobs WHERE schema_user=UPPER('&v_schema') AND broken='N' ORDER BY job;
PROMPT

PROMPT -- [E] CONFIRMAR ESTADO ANTES DE INICIAR LA CARGA
PROMPT
PROMPT SELECT 'Triggers deshabilitados: '||COUNT(*) FROM dba_triggers
PROMPT WHERE owner='&v_schema' AND status='DISABLED';
PROMPT

SPOOL OFF
PROMPT [OK] Generado: &f_precarga


-- ============================================================================
-- FICHERO 6: POST-CARGA (habilitar, reajustar secuencias, recompilar)
-- ============================================================================
SPOOL &f_postcarga
PROMPT -- ==================================================================
PROMPT -- dev_04_post_carga.sql — Ejecutar en DEV como SYSDBA DESPUES de cargar
SELECT '-- Generado desde PRE el ' || TO_CHAR(SYSDATE,'DD/MM/YYYY HH24:MI:SS') FROM DUAL;
PROMPT -- ==================================================================
PROMPT

PROMPT -- [A] REHABILITAR TRIGGERS
PROMPT
SELECT 'ALTER TRIGGER "'||UPPER('&v_schema')||'"."'||trigger_name||'" ENABLE;'
FROM   dba_triggers WHERE owner=UPPER('&v_schema') ORDER BY trigger_name;
PROMPT

PROMPT -- [B] REHABILITAR Y VALIDAR FOREIGN KEYS
PROMPT
SELECT 'ALTER TABLE "'||UPPER('&v_schema')||'"."'||table_name
    ||'" ENABLE NOVALIDATE CONSTRAINT "'||constraint_name||'";'
FROM   dba_constraints
WHERE  owner=UPPER('&v_schema') AND constraint_type='R'
ORDER BY table_name, constraint_name;
PROMPT

PROMPT -- [C] REHABILITAR JOBS DEL SCHEDULER
PROMPT
SELECT 'BEGIN DBMS_SCHEDULER.ENABLE(''"'||UPPER('&v_schema')||'"."'||job_name||'"''); END;'
    ||CHR(10)||'/'
FROM   dba_scheduler_jobs WHERE owner=UPPER('&v_schema') ORDER BY job_name;
PROMPT

PROMPT -- [D] REHABILITAR DBMS_JOB (legacy)
PROMPT
SELECT 'BEGIN DBMS_JOB.BROKEN('||job||',FALSE,SYSDATE); COMMIT; END;'||CHR(10)||'/'
FROM   dba_jobs WHERE schema_user=UPPER('&v_schema') ORDER BY job;
PROMPT

PROMPT -- [E] REAJUSTAR SECUENCIAS al maximo de los datos cargados
PROMPT --     Evita ORA-00001 (unique constraint) cuando aplicacion use NEXTVAL
PROMPT
DECLARE
  v_owner  VARCHAR2(128) := UPPER('&v_schema');
  v_col    VARCHAR2(128);
  v_table  VARCHAR2(128);
  v_max    NUMBER;
  v_curr   NUMBER;
  v_diff   NUMBER;
  v_sql    VARCHAR2(4000);
BEGIN
  -- Para cada secuencia busca la columna y tabla asociada por convencion de nombre
  -- Si el nombre no sigue convencion, ajustar manualmente
  FOR s IN (SELECT sequence_name, last_number FROM dba_sequences
            WHERE sequence_owner=v_owner ORDER BY sequence_name) LOOP
    BEGIN
      -- Busca columna DEFAULT que referencie esta secuencia
      SELECT c.table_name, c.column_name
      INTO   v_table, v_col
      FROM   dba_tab_columns c
      WHERE  c.owner = v_owner
        AND  UPPER(c.data_default) LIKE '%'||s.sequence_name||'%'
        AND  ROWNUM = 1;

      v_sql := 'SELECT NVL(MAX("'||v_col||'"),0) FROM "'||v_owner||'"."'||v_table||'"';
      EXECUTE IMMEDIATE v_sql INTO v_max;

      v_curr := s.last_number;
      v_diff := v_max - v_curr + 1;

      IF v_diff > 0 THEN
        DBMS_OUTPUT.PUT_LINE('-- Secuencia '||s.sequence_name
            ||' (tabla '||v_table||'.'||v_col||') MAX='||v_max||' CURR='||v_curr);
        DBMS_OUTPUT.PUT_LINE('ALTER SEQUENCE "'||v_owner||'"."'||s.sequence_name
            ||'" INCREMENT BY '||v_diff||';');
        DBMS_OUTPUT.PUT_LINE('SELECT "'||v_owner||'"."'||s.sequence_name
            ||'".NEXTVAL FROM DUAL;');
        DBMS_OUTPUT.PUT_LINE('ALTER SEQUENCE "'||v_owner||'"."'||s.sequence_name
            ||'" INCREMENT BY 1;');
        DBMS_OUTPUT.PUT_LINE('');
      ELSE
        DBMS_OUTPUT.PUT_LINE('-- Secuencia '||s.sequence_name||' OK (no requiere ajuste)');
      END IF;
    EXCEPTION WHEN NO_DATA_FOUND THEN
      DBMS_OUTPUT.PUT_LINE('-- ATENCION: '||s.sequence_name
          ||' — no se encontro columna DEFAULT asociada. Ajustar manualmente.');
      DBMS_OUTPUT.PUT_LINE('-- ALTER SEQUENCE "'||v_owner||'"."'||s.sequence_name
          ||'" INCREMENT BY <DIFERENCIA>;');
      DBMS_OUTPUT.PUT_LINE('-- SELECT "'||v_owner||'"."'||s.sequence_name||'".NEXTVAL FROM DUAL;');
      DBMS_OUTPUT.PUT_LINE('-- ALTER SEQUENCE "'||v_owner||'"."'||s.sequence_name
          ||'" INCREMENT BY 1;');
      DBMS_OUTPUT.PUT_LINE('');
    END;
  END LOOP;
END;
/
PROMPT

PROMPT -- [F] RECOMPILAR OBJETOS INVALIDOS
PROMPT
PROMPT BEGIN
PROMPT   DBMS_UTILITY.COMPILE_SCHEMA(schema => '&v_schema', compile_all => FALSE);
PROMPT END;
PROMPT /
PROMPT

SPOOL OFF
PROMPT [OK] Generado: &f_postcarga


-- ============================================================================
-- FICHERO 7: VALIDACION FINAL
-- ============================================================================
SPOOL &f_validacion
PROMPT -- ==================================================================
PROMPT -- dev_05_validacion.sql — Ejecutar en DEV como SYSDBA tras post-carga
SELECT '-- Generado desde PRE el ' || TO_CHAR(SYSDATE,'DD/MM/YYYY HH24:MI:SS') FROM DUAL;
PROMPT -- ==================================================================
PROMPT

PROMPT -- [1] OBJETOS INVALIDOS (debe ser 0)
SELECT object_type, object_name, status, last_ddl_time
FROM   dba_objects WHERE owner='&v_schema' AND status='INVALID'
ORDER BY object_type, object_name;

PROMPT
PROMPT -- [2] RESUMEN CONTEO POR TIPO
SELECT object_type,
       COUNT(*) total,
       SUM(CASE WHEN status='VALID'   THEN 1 ELSE 0 END) validos,
       SUM(CASE WHEN status='INVALID' THEN 1 ELSE 0 END) invalidos
FROM   dba_objects WHERE owner='&v_schema'
GROUP BY object_type ORDER BY object_type;

PROMPT
PROMPT -- [3] TRIGGERS Y JOBS: verificar estado final
SELECT trigger_name, status FROM dba_triggers
WHERE  owner='&v_schema' ORDER BY trigger_name;

SELECT job_name, enabled, state FROM dba_scheduler_jobs
WHERE  owner='&v_schema' ORDER BY job_name;

PROMPT
PROMPT -- [4] FOREIGN KEYS: verificar que estan habilitadas
SELECT constraint_name, table_name, status FROM dba_constraints
WHERE  owner='&v_schema' AND constraint_type='R'
ORDER BY table_name, constraint_name;

PROMPT
PROMPT -- [5] SECUENCIAS: valor actual vs maximo en tabla
DECLARE
  v_owner VARCHAR2(128):='&v_schema';
  v_col   VARCHAR2(128);
  v_table VARCHAR2(128);
  v_max   NUMBER;
BEGIN
  FOR s IN (SELECT sequence_name, last_number FROM dba_sequences
            WHERE sequence_owner=v_owner ORDER BY sequence_name) LOOP
    BEGIN
      SELECT c.table_name, c.column_name INTO v_table, v_col
      FROM   dba_tab_columns c
      WHERE  c.owner=v_owner AND UPPER(c.data_default) LIKE '%'||s.sequence_name||'%'
      AND    ROWNUM=1;
      EXECUTE IMMEDIATE 'SELECT NVL(MAX("'||v_col||'"),0) FROM "'||v_owner||'"."'||v_table||'"'
        INTO v_max;
      IF s.last_number <= v_max THEN
        DBMS_OUTPUT.PUT_LINE('*** ALERTA: '||s.sequence_name
            ||' NEXTVAL='||s.last_number||' <= MAX_ID='||v_max||' — riesgo de duplicado!');
      ELSE
        DBMS_OUTPUT.PUT_LINE('OK: '||s.sequence_name
            ||' NEXTVAL='||s.last_number||' > MAX_ID='||v_max);
      END IF;
    EXCEPTION WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('-- '||s.sequence_name||': revisar manualmente');
    END;
  END LOOP;
END;
/

PROMPT
PROMPT -- [6] CUOTAS: verificar espacio disponible
SELECT tablespace_name,
       CASE WHEN max_bytes=-1 THEN 'UNLIMITED'
            ELSE TO_CHAR(ROUND(max_bytes/1048576,2))||' MB' END cuota_max,
       ROUND(bytes/1048576,2)||' MB' usado
FROM   dba_ts_quotas WHERE username='&v_schema' ORDER BY 1;

SPOOL OFF
PROMPT [OK] Generado: &f_validacion


-- ============================================================================
-- RESUMEN FINAL
-- ============================================================================
SET HEADING ON
SET PAGESIZE 14
SET FEEDBACK ON
SET VERIFY   ON

PROMPT
PROMPT ============================================================
PROMPT  TODOS LOS FICHEROS GENERADOS:
PROMPT ============================================================
PROMPT
PROMPT  [REVISAR PRIMERO]
PROMPT  1. &f_nls        <- Comparar NLS con DEV antes de todo
PROMPT  2. &f_auditoria  <- Revisar inválidos, dependencias, perfil
PROMPT
PROMPT  [APLICAR EN DEV en este orden]
PROMPT  3. dev_01_usuario_grants.sql   -> Ajustar password, luego ejecutar
PROMPT  4. dev_02_ddl_objetos.sql      -> Crear todos los objetos
PROMPT  5. dev_03_pre_carga.sql        -> Deshabilitar triggers/jobs/FKs
PROMPT       >>> CARGA DE DATOS (equipo aplicacion) <<<
PROMPT  6. dev_04_post_carga.sql       -> Rehabilitar + reajustar secuencias
PROMPT  7. dev_05_validacion.sql       -> Validacion final
PROMPT
PROMPT  Conexion DEV: sqlplus / as sysdba (o /@DEV as sysdba)
PROMPT ============================================================
PROMPT

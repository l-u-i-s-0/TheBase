-- Limitar recursos del usuario DATALAKEGUIA sobre la BBDD de guia (Pre).
-- Resource Manager limita por consumer group, no por usuario directamente:
--   1) Crear consumer group       2) Crear plan + directiva con los limites
--   3) Mapear el usuario al grupo  4) Activar el plan
-- Limites solicitados:
--   cpu_p1              => 20      -- % CPU nivel 1
--   active_sess_pool_p1 => 75      -- sesiones activas concurrentes
--   max_est_exec_time   => 900     -- segundos
--   undo_pool           => 51200   -- KB (50 MB)
-- NOTA: ejecutar conectado a la PDB de la guia (no en el root si es CDB).

BEGIN
  DBMS_RESOURCE_MANAGER.CREATE_PENDING_AREA();

  -- 1. Consumer group para el usuario
  DBMS_RESOURCE_MANAGER.CREATE_CONSUMER_GROUP(
    consumer_group => 'GRP_DATALAKEGUIA',
    comment        => 'Limites para usuario DATALAKEGUIA - guia pre');

  -- 2. Plan de recursos
  DBMS_RESOURCE_MANAGER.CREATE_PLAN(
    plan    => 'PLAN_GUIA_PRE',
    comment => 'Plan limitacion DATALAKEGUIA');

  -- 3. Directiva con los limites solicitados
  DBMS_RESOURCE_MANAGER.CREATE_PLAN_DIRECTIVE(
    plan                => 'PLAN_GUIA_PRE',
    group_or_subplan    => 'GRP_DATALAKEGUIA',
    comment             => 'Limites DATALAKEGUIA',
    cpu_p1              => 20,      -- % CPU nivel 1
    active_sess_pool_p1 => 75,      -- sesiones activas concurrentes
    max_est_exec_time   => 900,     -- segundos
    undo_pool           => 51200);  -- KB (50 MB)

  -- 4. Directiva OTHER_GROUPS (obligatoria en todo plan)
  DBMS_RESOURCE_MANAGER.CREATE_PLAN_DIRECTIVE(
    plan             => 'PLAN_GUIA_PRE',
    group_or_subplan => 'OTHER_GROUPS',
    comment          => 'Resto de sesiones',
    cpu_p1           => 80);

  DBMS_RESOURCE_MANAGER.VALIDATE_PENDING_AREA();
  DBMS_RESOURCE_MANAGER.SUBMIT_PENDING_AREA();
END;
/

-- Mapear el usuario DATALAKEGUIA al consumer group
BEGIN
  DBMS_RESOURCE_MANAGER_PRIVS.GRANT_SWITCH_CONSUMER_GROUP(
    grantee_name   => 'DATALAKEGUIA',
    consumer_group => 'GRP_DATALAKEGUIA',
    grant_option   => FALSE);

  DBMS_RESOURCE_MANAGER.CREATE_PENDING_AREA();
  DBMS_RESOURCE_MANAGER.SET_CONSUMER_GROUP_MAPPING(
    attribute      => DBMS_RESOURCE_MANAGER.ORACLE_USER,
    value          => 'DATALAKEGUIA',
    consumer_group => 'GRP_DATALAKEGUIA');
  DBMS_RESOURCE_MANAGER.SUBMIT_PENDING_AREA();
END;
/

-- Activar el plan (usar FORCE: si hay ventanas de mantenimiento que lo sobreescriban)
ALTER SYSTEM SET RESOURCE_MANAGER_PLAN = 'PLAN_GUIA_PRE' SCOPE=BOTH;

-- Verificacion
-- SELECT name FROM v$rsrc_plan WHERE is_top_plan = 'TRUE';
-- SELECT attribute, value, consumer_group FROM dba_rsrc_group_mappings WHERE value = 'DATALAKEGUIA';
-- SELECT name, active_sessions, queue_length, consumed_cpu_time
--   FROM v$rsrc_consumer_group WHERE name = 'GRP_DATALAKEGUIA';

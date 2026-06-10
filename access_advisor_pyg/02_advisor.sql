-- ============================================================
-- 02_advisor.sql  -  Crear tarea y ejecutar Access Advisor
-- ============================================================
-- Requiere haber ejecutado 01_workload.sql en la misma sesion.
-- Crea la tarea, la vincula al workload y lanza el analisis.
-- Al terminar imprime el task_name para usar en 03_results.sql.
-- ============================================================

DECLARE
  -- Variables para parametros IN OUT de DBMS_ADVISOR
  -- (no se puede pasar un literal '&...' a un parametro IN OUT)
  v_task_name  VARCHAR2(100) := '&task_name';
  v_wkld_name  VARCHAR2(100) := '&wkld_name';
BEGIN
  DBMS_OUTPUT.PUT_LINE('==============================================');
  DBMS_OUTPUT.PUT_LINE(' 02_advisor  -  Ejecutar Access Advisor');
  DBMS_OUTPUT.PUT_LINE('==============================================');
  DBMS_OUTPUT.PUT_LINE(' Task     : ' || v_task_name);
  DBMS_OUTPUT.PUT_LINE(' Workload : ' || v_wkld_name);
  DBMS_OUTPUT.PUT_LINE('----------------------------------------------');

  -- 1. Crear la tarea del SQL Access Advisor (task_name es IN OUT)
  DBMS_ADVISOR.CREATE_TASK(
    advisor_name => 'SQL Access Advisor',
    task_name    => v_task_name
  );
  DBMS_OUTPUT.PUT_LINE(' Tarea creada.');

  -- 2. Vincular el workload a la tarea
  DBMS_ADVISOR.LINK_SQLWKLD_TASK(
    workload_name => v_wkld_name,
    task_name     => v_task_name
  );
  DBMS_OUTPUT.PUT_LINE(' Workload vinculado.');

  -- 3. Parametros del analisis
  --    ANALYSIS_SCOPE : INDEX | MVIEW | MVIEW_LOG | PARTITION | ALL
  --    MODE           : LIMITED (rapido) | COMPREHENSIVE (completo)
  DBMS_ADVISOR.SET_TASK_PARAMETER(v_task_name, 'ANALYSIS_SCOPE', 'ALL');
  DBMS_ADVISOR.SET_TASK_PARAMETER(v_task_name, 'MODE',           'COMPREHENSIVE');
  DBMS_OUTPUT.PUT_LINE(' Parametros: ANALYSIS_SCOPE=ALL, MODE=COMPREHENSIVE');

  -- 4. Ejecutar
  DBMS_OUTPUT.PUT_LINE(' Ejecutando... (puede tardar varios minutos)');
  DBMS_ADVISOR.EXECUTE_TASK(task_name => v_task_name);

  DBMS_OUTPUT.PUT_LINE('----------------------------------------------');
  DBMS_OUTPUT.PUT_LINE(' Estado: COMPLETADO');
  DBMS_OUTPUT.PUT_LINE('==============================================');
  DBMS_OUTPUT.PUT_LINE(' TASK NAME >>> ' || v_task_name);
  DBMS_OUTPUT.PUT_LINE('==============================================');
  DBMS_OUTPUT.PUT_LINE(' Siguiente: @access_advisor_pyg/03_results.sql');

EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('ERROR: ' || SQLERRM);
    BEGIN DBMS_ADVISOR.DELETE_TASK(v_task_name);    EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DBMS_ADVISOR.DELETE_SQLWKLD(v_wkld_name); EXCEPTION WHEN OTHERS THEN NULL; END;
    RAISE;
END;
/

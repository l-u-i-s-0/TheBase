-- ============================================================
-- 02_advisor.sql  -  Crear tarea y ejecutar Access Advisor
-- ============================================================
-- Requiere haber ejecutado 01_workload.sql en la misma sesion.
-- Crea la tarea, la vincula al workload y lanza el analisis.
-- Al terminar imprime el task_name para usar en 03_results.sql.
-- ============================================================

DECLARE
BEGIN
  DBMS_OUTPUT.PUT_LINE('==============================================');
  DBMS_OUTPUT.PUT_LINE(' 02_advisor  -  Ejecutar Access Advisor');
  DBMS_OUTPUT.PUT_LINE('==============================================');
  DBMS_OUTPUT.PUT_LINE(' Task     : &task_name');
  DBMS_OUTPUT.PUT_LINE(' Workload : &wkld_name');
  DBMS_OUTPUT.PUT_LINE('----------------------------------------------');

  -- 1. Crear la tarea del SQL Access Advisor
  DBMS_ADVISOR.CREATE_TASK(
    advisor_name => 'SQL Access Advisor',
    task_name    => '&task_name'
  );
  DBMS_OUTPUT.PUT_LINE(' Tarea creada.');

  -- 2. Vincular el workload a la tarea
  DBMS_ADVISOR.LINK_SQLWKLD_TASK(
    workload_name => '&wkld_name',
    task_name     => '&task_name'
  );
  DBMS_OUTPUT.PUT_LINE(' Workload vinculado.');

  -- 3. Parametros del analisis
  --    ANALYSIS_SCOPE : INDEX | MVIEW | MVIEW_LOG | PARTITION | ALL
  --    MODE           : LIMITED (rapido) | COMPREHENSIVE (completo)
  DBMS_ADVISOR.SET_TASK_PARAMETER('&task_name', 'ANALYSIS_SCOPE', 'ALL');
  DBMS_ADVISOR.SET_TASK_PARAMETER('&task_name', 'MODE',           'COMPREHENSIVE');
  DBMS_OUTPUT.PUT_LINE(' Parametros: ANALYSIS_SCOPE=ALL, MODE=COMPREHENSIVE');

  -- 4. Ejecutar
  DBMS_OUTPUT.PUT_LINE(' Ejecutando... (puede tardar varios minutos)');
  DBMS_ADVISOR.EXECUTE_TASK(task_name => '&task_name');

  DBMS_OUTPUT.PUT_LINE('----------------------------------------------');
  DBMS_OUTPUT.PUT_LINE(' Estado: COMPLETADO');
  DBMS_OUTPUT.PUT_LINE('==============================================');
  DBMS_OUTPUT.PUT_LINE(' TASK NAME >>> &task_name');
  DBMS_OUTPUT.PUT_LINE('==============================================');
  DBMS_OUTPUT.PUT_LINE(' Siguiente: @access_advisor_pyg/03_results.sql');

EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('ERROR: ' || SQLERRM);
    BEGIN DBMS_ADVISOR.DELETE_TASK('&task_name');    EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DBMS_ADVISOR.DELETE_SQLWKLD('&wkld_name'); EXCEPTION WHEN OTHERS THEN NULL; END;
    RAISE;
END;
/

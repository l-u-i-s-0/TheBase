-- ============================================================
-- SQL Access Advisor - Proceso PYG / GUIA
-- ============================================================
-- Sesion origen:
--   USERNAME : GUIA
--   SID      : 2297
--   Serial#  : 33661
--   sql_id   : 90zdv03f74mvb
--
-- Carga en el workload:
--   1. El SQL especifico por sql_id (entrada principal)
--   2. Todos los SQLs del cursor cache que referencian
--      cualquiera de las 41 tablas del proceso
--
-- Requisito: privilegio ADVISOR  +  acceso a v$sql, v$sql_plan
-- ============================================================

SET SERVEROUTPUT ON SIZE UNLIMITED
SET LONG          65536
SET LONGCHUNKSIZE 65536
SET LINESIZE      200
SET PAGESIZE      200

DECLARE

  -- ----------------------------------------------------------
  -- DATOS DE LA SESION
  -- ----------------------------------------------------------
  v_sql_id    CONSTANT VARCHAR2(13) := '90zdv03f74mvb';

  -- ----------------------------------------------------------
  -- TABLAS DEL PROCESO  (owner.tabla  o  solo tabla)
  -- El filtro usa solo el nombre de objeto (sin schema)
  -- para capturar independientemente del esquema en v$sql_plan
  -- ----------------------------------------------------------
  TYPE t_varchar_list IS TABLE OF VARCHAR2(200);

  v_tables t_varchar_list := t_varchar_list(
    -- Schema SASGUIA
    'SASGUIA.PYGCONSOLIDACION',
    'SASGUIA.PYGDESCERRORPER',
    'SASGUIA.PYGAJCONT',
    'SASGUIA.PYGGASTOSREP',
    'SASGUIA.PYGEMPRCTCOST',
    'SASGUIA.PYGGASTEMP',
    'SASGUIA.PYGCTRCOST',
    'SASGUIA.PYGTIFGAST',
    'SASGUIA.PYGGASTOSTIPOG',
    'SASGUIA.PYGPRODCOM',
    'SASGUIA.PYGPRODCNICOST',
    'SASGUIA.PYGGASTOSPROD',
    'SASGUIA.PYGVAROP',
    'SASGUIA.PYGIMPORTES',
    'SASGUIA.PYGVAASIGGAST',
    'SASGUIA.PYGCASTOPER',
    'SASGUIA.PYGCERRORES',
    -- Schema GUIA - tablas temporales del proceso
    'GUIA.TMP_PERIMETRO_OF',
    'GUIA.PYG_TMP_PERIMETRO_ITACA',
    'GUIA.PYG_TMP_GASTOSPROD_DRIVERS',
    'GUIA.PYG_TMP_VASTIG',
    'GUIA.PYG_TMP_GASTOSPROD_ITACA',
    'GUIA.PYG_TMP_SOCIED_PER',
    'GUIA.PYG_TMP_HOLDING_PER',
    'GUIA.PYG_TMP_GASTOSPROD_SOC',
    'GUIA.PYG_TMP_SUCURS_PER',
    'GUIA.PYG_TMP_ZONA_PER',
    'GUIA.PYG_TMP_REG_PER',
    'GUIA.PYG_TMP_GASTOSPROD_FINAL',
    'GUIA.PYG_TMP_FILTRO_SUC',
    -- Sin schema explicito (resolver por contexto de sesion)
    'PYGCUEGAST',
    'DINCWA24',
    'DINUMA25',
    'DINUMA01',
    'TNP_GASTOSREP_PYG',
    'TNP_GASTOSREP_AGRUF',
    'TNP_GASTOSREP_PYG_EMP',
    'SICPPFUR51',
    'SIASGUIA.PYGCONSOLIDACON',
    'PYGREGACTIVIDAD'
  );
  -- ----------------------------------------------------------

  v_task_name  VARCHAR2(100);
  v_wkld_name  VARCHAR2(100);
  v_stmt_count PLS_INTEGER := 0;
  v_in_list    VARCHAR2(32767);
  v_dyn_sql    VARCHAR2(32767);
  v_obj_name   VARCHAR2(128);

  -- SQL especifico por sql_id
  v_sql_text   CLOB;
  v_executions NUMBER;
  v_elapsed    NUMBER;
  v_cpu        NUMBER;
  v_gets       NUMBER;

  TYPE t_sql_rec IS RECORD (
    sql_id       VARCHAR2(13),
    sql_text     CLOB,
    executions   NUMBER,
    elapsed_time NUMBER,
    cpu_time     NUMBER,
    buffer_gets  NUMBER
  );
  TYPE t_sql_tab IS TABLE OF t_sql_rec;
  v_sqls t_sql_tab := t_sql_tab();

  -- --------------------------------------------------------
  PROCEDURE add_to_workload(
    p_text     IN CLOB,
    p_exec     IN NUMBER,
    p_elapsed  IN NUMBER,
    p_cpu      IN NUMBER,
    p_gets     IN NUMBER,
    p_action   IN VARCHAR2 DEFAULT NULL
  ) IS
  BEGIN
    DBMS_ADVISOR.ADD_SQLWKLD_STATEMENT(
      workload_name  => v_wkld_name,
      module         => 'ACC_ADV_PYG',
      action         => p_action,
      cpu_time       => NVL(p_cpu,     0),
      elapsed_time   => NVL(p_elapsed, 0),
      disk_reads     => 0,
      buffer_gets    => NVL(p_gets,    0),
      rows_processed => 0,
      executions     => NVL(p_exec,    1),
      username       => 'GUIA',
      sql_text       => p_text
    );
    v_stmt_count := v_stmt_count + 1;
  EXCEPTION
    WHEN OTHERS THEN NULL;
  END add_to_workload;

BEGIN
  v_task_name := 'ACC_ADV_PYG_' || TO_CHAR(SYSDATE, 'YYYYMMDD_HH24MISS');
  v_wkld_name := 'WKL_PYG_'     || TO_CHAR(SYSDATE, 'YYYYMMDD_HH24MISS');

  DBMS_OUTPUT.PUT_LINE('==============================================');
  DBMS_OUTPUT.PUT_LINE(' SQL Access Advisor - Proceso PYG/GUIA');
  DBMS_OUTPUT.PUT_LINE('==============================================');
  DBMS_OUTPUT.PUT_LINE(' sql_id   : ' || v_sql_id);
  DBMS_OUTPUT.PUT_LINE(' Task     : ' || v_task_name);
  DBMS_OUTPUT.PUT_LINE(' Workload : ' || v_wkld_name);
  DBMS_OUTPUT.PUT_LINE(' Tablas   : ' || v_tables.COUNT);
  DBMS_OUTPUT.PUT_LINE('----------------------------------------------');

  -- ==========================================================
  -- PASO 1: Cargar el SQL principal por sql_id
  -- ==========================================================
  BEGIN
    SELECT sql_fulltext, executions, elapsed_time, cpu_time, buffer_gets
    INTO   v_sql_text, v_executions, v_elapsed, v_cpu, v_gets
    FROM   v$sql
    WHERE  sql_id = v_sql_id
    AND    ROWNUM  = 1;

    DBMS_OUTPUT.PUT_LINE(' SQL ' || v_sql_id || ' encontrado en cursor cache');

    -- Crear workload y agregar el SQL principal
    DBMS_ADVISOR.CREATE_SQLWKLD(workload_name => v_wkld_name);
    add_to_workload(v_sql_text, v_executions, v_elapsed, v_cpu, v_gets,
                    'SQL_ID_' || v_sql_id);

  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      DBMS_OUTPUT.PUT_LINE(' AVISO: sql_id ' || v_sql_id ||
                           ' no esta en cursor cache (shared pool purgado?)');
      DBMS_OUTPUT.PUT_LINE('        Continuando solo con busqueda por tablas...');
      DBMS_ADVISOR.CREATE_SQLWKLD(workload_name => v_wkld_name);
  END;

  -- ==========================================================
  -- PASO 2: Buscar SQLs adicionales por nombre de tabla
  --         Extrae solo el nombre de objeto (sin schema)
  -- ==========================================================
  FOR i IN 1..v_tables.COUNT LOOP
    -- Extraer nombre de tabla: lo que va despues del ultimo punto
    v_obj_name := SUBSTR(v_tables(i), INSTR(v_tables(i), '.') + 1);

    IF i = 1 THEN
      v_in_list := '''' || v_obj_name || '''';
    ELSE
      v_in_list := v_in_list || ',''' || v_obj_name || '''';
    END IF;
  END LOOP;

  v_dyn_sql :=
    'SELECT DISTINCT s.sql_id, s.sql_fulltext, s.executions, ' ||
    '                s.elapsed_time, s.cpu_time, s.buffer_gets ' ||
    'FROM   v$sql s ' ||
    'WHERE  s.executions > 0 ' ||
    '  AND  s.sql_id != ''' || v_sql_id || ''' ' ||   -- evitar duplicar el SQL principal
    '  AND  EXISTS ( ' ||
    '    SELECT 1 FROM v$sql_plan p ' ||
    '    WHERE  p.sql_id      = s.sql_id ' ||
    '    AND    p.object_name IN (' || v_in_list || ') ' ||
    '  ) ' ||
    'ORDER BY s.elapsed_time DESC';

  EXECUTE IMMEDIATE v_dyn_sql BULK COLLECT INTO v_sqls;

  DBMS_OUTPUT.PUT_LINE(' SQLs adicionales por tabla : ' || v_sqls.COUNT);

  FOR i IN 1..v_sqls.COUNT LOOP
    add_to_workload(
      v_sqls(i).sql_text,
      v_sqls(i).executions,
      v_sqls(i).elapsed_time,
      v_sqls(i).cpu_time,
      v_sqls(i).buffer_gets
    );
  END LOOP;

  DBMS_OUTPUT.PUT_LINE(' Total SQLs en workload     : ' || v_stmt_count);
  DBMS_OUTPUT.PUT_LINE('----------------------------------------------');

  IF v_stmt_count = 0 THEN
    DBMS_OUTPUT.PUT_LINE(' ERROR: Workload vacio - no se puede continuar.');
    DBMS_OUTPUT.PUT_LINE('        Verifica que el sql_id o las tablas esten');
    DBMS_OUTPUT.PUT_LINE('        todavia en el shared pool/cursor cache.');
    DBMS_ADVISOR.DELETE_SQLWKLD(workload_name => v_wkld_name);
    RETURN;
  END IF;

  -- ==========================================================
  -- PASO 3: Crear y configurar la tarea del Access Advisor
  -- ==========================================================
  DBMS_ADVISOR.CREATE_TASK(
    advisor_name => 'SQL Access Advisor',
    task_name    => v_task_name
  );

  DBMS_ADVISOR.LINK_SQLWKLD_TASK(
    workload_name => v_wkld_name,
    task_name     => v_task_name
  );

  -- ANALYSIS_SCOPE: INDEX | MVIEW | MVIEW_LOG | PARTITION | ALL
  -- MODE          : LIMITED (rapido) | COMPREHENSIVE (completo)
  DBMS_ADVISOR.SET_TASK_PARAMETER(v_task_name, 'ANALYSIS_SCOPE', 'ALL');
  DBMS_ADVISOR.SET_TASK_PARAMETER(v_task_name, 'MODE',           'COMPREHENSIVE');

  -- ==========================================================
  -- PASO 4: Ejecutar
  -- ==========================================================
  DBMS_OUTPUT.PUT_LINE(' Ejecutando Access Advisor...');
  DBMS_ADVISOR.EXECUTE_TASK(task_name => v_task_name);

  DBMS_OUTPUT.PUT_LINE(' Estado  : completado');
  DBMS_OUTPUT.PUT_LINE('==============================================');
  DBMS_OUTPUT.PUT_LINE(' TASK NAME >>> ' || v_task_name);
  DBMS_OUTPUT.PUT_LINE('==============================================');
  DBMS_OUTPUT.PUT_LINE('');
  DBMS_OUTPUT.PUT_LINE(' Consulta resultados con:');
  DBMS_OUTPUT.PUT_LINE('   DEFINE task_name = ''' || v_task_name || '''');

EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('ERROR: ' || SQLERRM);
    BEGIN DBMS_ADVISOR.DELETE_TASK(v_task_name);     EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DBMS_ADVISOR.DELETE_SQLWKLD(v_wkld_name);  EXCEPTION WHEN OTHERS THEN NULL; END;
    RAISE;
END;
/


-- ============================================================
-- RESULTADOS
-- ============================================================
-- Tras ejecutar el bloque de arriba, copia el TASK NAME
-- impreso y sustituyelo en la variable de abajo.
-- Despues ejecuta los SELECTs que necesites.

-- DEFINE task_name = 'ACC_ADV_PYG_YYYYMMDD_HH24MISS'

/*
-- 1. Resumen de recomendaciones ordenadas por beneficio
COLUMN rec_id        FORMAT 999
COLUMN benefit_type  FORMAT A15
COLUMN benefit_value FORMAT 99999999999
COLUMN message       FORMAT A70 WRAP

SELECT rec_id, benefit_type, benefit_value, message
FROM   user_advisor_recommendations
WHERE  task_name = '&task_name'
ORDER BY benefit_value DESC;


-- 2. DDLs recomendados (CREATE INDEX, CREATE MVIEW, etc.)
COLUMN command  FORMAT A12
COLUMN attr1    FORMAT A55 WRAP
COLUMN attr2    FORMAT A20
COLUMN attr3    FORMAT A10

SELECT a.rec_id, a.command, a.attr1, a.attr2, a.attr3
FROM   user_advisor_actions a
WHERE  a.task_name = '&task_name'
ORDER BY a.rec_id;


-- 3. Script SQL completo listo para ejecutar
SET LONG 100000
SELECT DBMS_ADVISOR.GET_TASK_SCRIPT('&task_name') AS ddl_script
FROM   DUAL;


-- 4. Limpiar cuando ya no se necesite
-- EXEC DBMS_ADVISOR.DELETE_TASK('&task_name');
*/

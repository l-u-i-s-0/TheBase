-- ============================================================
-- 01_workload.sql  -  Configuracion + Crear workload y cargar SQLs
-- ============================================================
-- Sesion origen: USERNAME=GUIA  SID=2297  Serial#=33661
--
-- Edita sql_id, task_name y wkld_name si es necesario.
--
-- Orden de ejecucion (misma sesion SQL*Plus):
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

DECLARE

  -- Tablas del proceso PYG (owner.tabla o solo tabla)
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
    -- Schema GUIA - tablas temporales
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
    -- Sin schema explicito
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

  -- Variables para parametros IN OUT de DBMS_ADVISOR
  -- (no se puede pasar un literal '&...' a un parametro IN OUT)
  v_wkld_name  VARCHAR2(100)   := '&wkld_name';

  v_stmt_count PLS_INTEGER := 0;
  v_in_list    VARCHAR2(32767);
  v_dyn_sql    VARCHAR2(32767);
  v_obj_name   VARCHAR2(128);

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

  PROCEDURE add_stmt(
    p_text    IN CLOB,
    p_exec    IN NUMBER,
    p_elapsed IN NUMBER,
    p_cpu     IN NUMBER,
    p_gets    IN NUMBER,
    p_action  IN VARCHAR2 DEFAULT NULL
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
  END;

BEGIN
  DBMS_OUTPUT.PUT_LINE('==============================================');
  DBMS_OUTPUT.PUT_LINE(' 01_workload  -  Crear workload y cargar SQLs');
  DBMS_OUTPUT.PUT_LINE('==============================================');
  DBMS_OUTPUT.PUT_LINE(' Workload : &wkld_name');
  DBMS_OUTPUT.PUT_LINE(' sql_id   : &sql_id');

  DBMS_ADVISOR.CREATE_SQLWKLD(workload_name => v_wkld_name);
  DBMS_OUTPUT.PUT_LINE(' Workload creado.');

  -- A) SQL principal por sql_id
  BEGIN
    SELECT sql_fulltext, executions, elapsed_time, cpu_time, buffer_gets
    INTO   v_sql_text, v_executions, v_elapsed, v_cpu, v_gets
    FROM   v$sql
    WHERE  sql_id = '&sql_id'
    AND    ROWNUM  = 1;

    add_stmt(v_sql_text, v_executions, v_elapsed, v_cpu, v_gets,
             'SQL_ID_&sql_id');
    DBMS_OUTPUT.PUT_LINE(' SQL principal cargado (sql_id=&sql_id)');
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      DBMS_OUTPUT.PUT_LINE(' AVISO: sql_id &sql_id no esta en cursor cache.');
      DBMS_OUTPUT.PUT_LINE('        Continuando con busqueda por tablas...');
  END;

  -- B) SQLs adicionales filtrando por nombre de tabla en v$sql_plan
  FOR i IN 1..v_tables.COUNT LOOP
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
    '  AND  s.sql_id != ''&sql_id'' ' ||
    '  AND  EXISTS ( ' ||
    '    SELECT 1 FROM v$sql_plan p ' ||
    '    WHERE  p.sql_id = s.sql_id ' ||
    '    AND    p.object_name IN (' || v_in_list || ') ' ||
    '  ) ' ||
    'ORDER BY s.elapsed_time DESC';

  EXECUTE IMMEDIATE v_dyn_sql BULK COLLECT INTO v_sqls;
  DBMS_OUTPUT.PUT_LINE(' SQLs adicionales encontrados: ' || v_sqls.COUNT);

  FOR i IN 1..v_sqls.COUNT LOOP
    add_stmt(v_sqls(i).sql_text, v_sqls(i).executions,
             v_sqls(i).elapsed_time, v_sqls(i).cpu_time, v_sqls(i).buffer_gets);
  END LOOP;

  DBMS_OUTPUT.PUT_LINE('----------------------------------------------');
  DBMS_OUTPUT.PUT_LINE(' Total SQLs en workload: ' || v_stmt_count);

  IF v_stmt_count = 0 THEN
    DBMS_OUTPUT.PUT_LINE(' ERROR: Workload vacio. Verifica cursor cache.');
    DBMS_ADVISOR.DELETE_SQLWKLD(workload_name => v_wkld_name);
    RETURN;
  END IF;

  DBMS_OUTPUT.PUT_LINE(' OK - Siguiente: @access_advisor_pyg/02_advisor.sql');
  DBMS_OUTPUT.PUT_LINE('==============================================');

EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('ERROR: ' || SQLERRM);
    BEGIN DBMS_ADVISOR.DELETE_SQLWKLD('&wkld_name'); EXCEPTION WHEN OTHERS THEN NULL; END;
    RAISE;
END;
/

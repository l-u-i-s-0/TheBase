-- ============================================================
-- SQL Access Advisor - Multiple Tables
-- ============================================================
-- Busca en el cursor cache todos los SQLs que referencian
-- las tablas indicadas y ejecuta el SQL Access Advisor para
-- recomendar indices, vistas materializadas y particionamiento.
--
-- Requisito: Privilegios ADVISOR y acceso a v$sql, v$sql_plan
--
-- Uso:
--   1. Modifica la lista de tablas en la seccion CONFIGURACION
--   2. Ejecuta el bloque principal
--   3. Usa el task_name impreso para consultar recomendaciones
-- ============================================================

SET SERVEROUTPUT ON SIZE UNLIMITED
SET LONG      65536
SET LONGCHUNKSIZE 65536
SET LINESIZE  200
SET PAGESIZE  200

-- ============================================================
-- BLOQUE PRINCIPAL: Crear workload y ejecutar Access Advisor
-- ============================================================
DECLARE

  -- ----------------------------------------------------------
  -- CONFIGURACION: Agrega o quita tablas segun necesites
  -- ----------------------------------------------------------
  TYPE t_varchar_list IS TABLE OF VARCHAR2(128);

  v_tables t_varchar_list := t_varchar_list(
    'EMPLOYEES',         -- <-- tabla 1
    'DEPARTMENTS',       -- <-- tabla 2
    'JOBS'               -- <-- tabla 3  (agrega mas lineas aqui)
  );
  -- ----------------------------------------------------------

  v_task_name  VARCHAR2(100);
  v_wkld_name  VARCHAR2(100);
  v_stmt_count PLS_INTEGER := 0;
  v_in_list    VARCHAR2(4000);
  v_sql        VARCHAR2(4000);

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

BEGIN
  v_task_name := 'ACC_ADV_' || TO_CHAR(SYSDATE, 'YYYYMMDD_HH24MISS');
  v_wkld_name := 'WKL_'     || TO_CHAR(SYSDATE, 'YYYYMMDD_HH24MISS');

  DBMS_OUTPUT.PUT_LINE('===============================================');
  DBMS_OUTPUT.PUT_LINE(' SQL Access Advisor - Multiples Tablas');
  DBMS_OUTPUT.PUT_LINE('===============================================');
  DBMS_OUTPUT.PUT_LINE(' Task    : ' || v_task_name);
  DBMS_OUTPUT.PUT_LINE(' Workload: ' || v_wkld_name);
  DBMS_OUTPUT.PUT_LINE(' Tablas  : ' || v_tables.COUNT);
  DBMS_OUTPUT.PUT_LINE('-----------------------------------------------');

  -- Construir lista IN para el query dinamico
  FOR i IN 1..v_tables.COUNT LOOP
    IF i = 1 THEN
      v_in_list := '''' || v_tables(i) || '''';
    ELSE
      v_in_list := v_in_list || ',''' || v_tables(i) || '''';
    END IF;
    DBMS_OUTPUT.PUT_LINE(' Tabla ' || LPAD(i,2) || ': ' || v_tables(i));
  END LOOP;
  DBMS_OUTPUT.PUT_LINE('-----------------------------------------------');

  -- Buscar SQLs en cursor cache que referencian las tablas
  v_sql :=
    'SELECT DISTINCT s.sql_id, s.sql_fulltext, s.executions, ' ||
    '                s.elapsed_time, s.cpu_time, s.buffer_gets ' ||
    'FROM   v$sql s ' ||
    'WHERE  s.executions > 0 ' ||
    '  AND  EXISTS ( ' ||
    '         SELECT 1 FROM v$sql_plan p ' ||
    '         WHERE  p.sql_id     = s.sql_id ' ||
    '         AND    p.object_name IN (' || v_in_list || ') ' ||
    '       ) ' ||
    'ORDER BY s.elapsed_time DESC';

  EXECUTE IMMEDIATE v_sql
    BULK COLLECT INTO v_sqls;

  DBMS_OUTPUT.PUT_LINE(' SQLs encontrados en cursor cache: ' || v_sqls.COUNT);

  IF v_sqls.COUNT = 0 THEN
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('AVISO: No se encontraron SQLs en cursor cache para');
    DBMS_OUTPUT.PUT_LINE('       las tablas indicadas. Posibles causas:');
    DBMS_OUTPUT.PUT_LINE('  - Las tablas no han sido accedidas recientemente');
    DBMS_OUTPUT.PUT_LINE('  - El cursor cache fue purgado (shared pool flush)');
    DBMS_OUTPUT.PUT_LINE('  - Los nombres de tabla no coinciden (verifca mayusculas)');
    RETURN;
  END IF;

  -- 1. Crear workload
  DBMS_ADVISOR.CREATE_SQLWKLD(workload_name => v_wkld_name);

  -- 2. Agregar cada SQL al workload
  FOR i IN 1..v_sqls.COUNT LOOP
    BEGIN
      DBMS_ADVISOR.ADD_SQLWKLD_STATEMENT(
        workload_name  => v_wkld_name,
        module         => 'ACCESS_ADVISOR',
        action         => NULL,
        cpu_time       => NVL(v_sqls(i).cpu_time,     0),
        elapsed_time   => NVL(v_sqls(i).elapsed_time, 0),
        disk_reads     => 0,
        buffer_gets    => NVL(v_sqls(i).buffer_gets,  0),
        rows_processed => 0,
        executions     => NVL(v_sqls(i).executions,   1),
        username       => USER,
        sql_text       => v_sqls(i).sql_text
      );
      v_stmt_count := v_stmt_count + 1;
    EXCEPTION
      WHEN OTHERS THEN NULL; -- Ignorar DDLs o SQLs invalidos
    END;
  END LOOP;

  DBMS_OUTPUT.PUT_LINE(' SQLs cargados en workload    : ' || v_stmt_count);

  IF v_stmt_count = 0 THEN
    DBMS_OUTPUT.PUT_LINE('AVISO: Ninguno de los SQLs pudo cargarse al workload.');
    DBMS_ADVISOR.DELETE_SQLWKLD(workload_name => v_wkld_name);
    RETURN;
  END IF;

  -- 3. Crear tarea del SQL Access Advisor
  DBMS_ADVISOR.CREATE_TASK(
    advisor_name => 'SQL Access Advisor',
    task_name    => v_task_name
  );

  -- 4. Vincular workload a la tarea
  DBMS_ADVISOR.LINK_SQLWKLD_TASK(
    workload_name => v_wkld_name,
    task_name     => v_task_name
  );

  -- 5. Configurar parametros del analisis
  --    ANALYSIS_SCOPE: INDEX | MVIEW | MVIEW_LOG | PARTITION | ALL
  --    MODE          : LIMITED (rapido) | COMPREHENSIVE (completo)
  DBMS_ADVISOR.SET_TASK_PARAMETER(v_task_name, 'ANALYSIS_SCOPE', 'ALL');
  DBMS_ADVISOR.SET_TASK_PARAMETER(v_task_name, 'MODE',           'COMPREHENSIVE');

  -- 6. Ejecutar el advisor
  DBMS_OUTPUT.PUT_LINE('-----------------------------------------------');
  DBMS_OUTPUT.PUT_LINE(' Ejecutando Access Advisor...');
  DBMS_ADVISOR.EXECUTE_TASK(task_name => v_task_name);

  DBMS_OUTPUT.PUT_LINE(' Estado: completado');
  DBMS_OUTPUT.PUT_LINE('===============================================');
  DBMS_OUTPUT.PUT_LINE(' TASK NAME: ' || v_task_name);
  DBMS_OUTPUT.PUT_LINE('===============================================');
  DBMS_OUTPUT.PUT_LINE('');
  DBMS_OUTPUT.PUT_LINE(' Para ver recomendaciones ejecuta la seccion');
  DBMS_OUTPUT.PUT_LINE(' RESULTADOS al final de este script, usando:');
  DBMS_OUTPUT.PUT_LINE('   DEFINE task_name = ''' || v_task_name || '''');

EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('ERROR: ' || SQLERRM);
    BEGIN DBMS_ADVISOR.DELETE_TASK(task_name => v_task_name);     EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DBMS_ADVISOR.DELETE_SQLWKLD(workload_name => v_wkld_name); EXCEPTION WHEN OTHERS THEN NULL; END;
    RAISE;
END;
/


-- ============================================================
-- RESULTADOS: Consultar recomendaciones del task ejecutado
-- ============================================================
-- Reemplaza el valor de task_name con el impreso arriba o
-- ejecuta directamente tras el bloque principal.

-- DEFINE task_name = 'ACC_ADV_YYYYMMDD_HH24MISS'

/*
-- Resumen de recomendaciones
COLUMN task_name     FORMAT A35
COLUMN rec_id        FORMAT 999
COLUMN benefit_type  FORMAT A15
COLUMN benefit_value FORMAT 99999999999
COLUMN message       FORMAT A70 WRAP

SELECT rec_id,
       benefit_type,
       benefit_value,
       message
FROM   user_advisor_recommendations
WHERE  task_name = '&task_name'
ORDER BY benefit_value DESC;


-- Detalle de acciones (DDLs sugeridos: CREATE INDEX, etc.)
COLUMN command  FORMAT A12
COLUMN attr1    FORMAT A50 WRAP
COLUMN attr2    FORMAT A20
COLUMN attr3    FORMAT A10

SELECT a.rec_id,
       a.command,
       a.attr1,
       a.attr2,
       a.attr3
FROM   user_advisor_actions a
WHERE  a.task_name = '&task_name'
ORDER BY a.rec_id;


-- Script SQL con todos los DDLs recomendados
SELECT DBMS_ADVISOR.GET_TASK_SCRIPT('&task_name') AS script
FROM   DUAL;


-- Limpiar tarea y workload cuando ya no se necesiten
-- EXEC DBMS_ADVISOR.DELETE_TASK('&task_name');
*/

-- Saltarse SOLO la apertura del sabado 13-jun-2026.
-- Se mueve la fecha de referencia (START_DATE) al dia siguiente de ese sabado.
-- El scheduler recalcula la proxima apertura como el primer sabado que cumple
-- el REPEAT_INTERVAL a partir de esa fecha => sabado 20-jun-2026.
-- Las aperturas posteriores siguen su cadencia semanal normal.
BEGIN
  DBMS_SCHEDULER.SET_ATTRIBUTE(
    name      => 'SATURDAY_WINDOW',
    attribute => 'START_DATE',
    value     => TIMESTAMP '2026-06-14 00:00:00'
  );
END;
/

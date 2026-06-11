BEGIN
  DBMS_SCHEDULER.SET_ATTRIBUTE(
    name      => 'SATURDAY_WINDOW',
    attribute => 'START_DATE',
    value     => SYSTIMESTAMP + INTERVAL '7' DAY
  );
END;
/

BEGIN
  DBMS_SCHEDULER.SET_ATTRIBUTE(
    name      => 'SATURDAY_WINDOW',
    attribute => 'NEXT_START_DATE',
    value     => SYSTIMESTAMP + INTERVAL '7' DAY
  );
END;
/

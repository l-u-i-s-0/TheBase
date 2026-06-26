impdp "/ as sysdba" schemas=JOBPROCESOR content=METADATA_ONLY directory=DATA_PUMP_DIR dumpfile=JOBPROCESOR_ddl.dmp logfile=JOBPROCESOR_ddl_imp.log table_exists_action=REPLACE

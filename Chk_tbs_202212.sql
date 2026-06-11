-- Check 1: Segmentos activos en los tablespaces
SELECT owner, segment_name, segment_type
FROM dba_segments
WHERE tablespace_name IN (
'TBHIS_202212','TBOUT_202212','TBSRD_202212','TBCGB_202212','TBCPT_202212','TBDAT_202212','TBRDM_202212','TBESG_202212'
);

-- Check 2: Constraints cruzadas con otros tablespaces
SELECT owner, constraint_name, table_name
FROM dba_constraints
WHERE status = 'ENABLED'
  AND r_owner IN (
    SELECT owner FROM dba_segments
    WHERE tablespace_name IN ('TBHIS_202212','TBOUT_202212','TBSRD_202212','TBCGB_202212','TBCPT_202212','TBDAT_202212','TBRDM_202212','TBESG_202212'));

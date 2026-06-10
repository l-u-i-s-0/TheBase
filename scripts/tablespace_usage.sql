COLUMN tablespace_name FORMAT A20

SELECT t.tablespace_name,
       ROUND(SUM(d.bytes) / 1024 / 1024, 2) AS "TOTAL_MB",
       ROUND(SUM(f.bytes) / 1024 / 1024, 2) AS "FREE_MB",
       ROUND((SUM(d.bytes) - SUM(f.bytes)) / 1024 / 1024, 2) AS "USED_MB",
       ROUND(100 * (SUM(f.bytes) / SUM(d.bytes)), 2) AS "%_FREE"
FROM dba_data_files d
JOIN dba_free_space f ON d.tablespace_name = f.tablespace_name
JOIN dba_tablespaces t ON d.tablespace_name = t.tablespace_name
GROUP BY t.tablespace_name
ORDER BY t.tablespace_name;

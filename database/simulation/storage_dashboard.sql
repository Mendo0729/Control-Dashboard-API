\pset border 2
\pset null '(null)'

\echo === Resumen de almacenamiento ===
SELECT current_database() AS database_name,
       pg_size_pretty(pg_database_size(current_database())) AS total_size,
       pg_database_size(current_database()) AS total_bytes;

\echo === Tamaño por tabla ===
SELECT relname AS table_name,
       n_live_tup AS live_rows,
       n_dead_tup AS dead_rows,
       pg_size_pretty(pg_total_relation_size(relid)) AS total_size,
       pg_size_pretty(pg_relation_size(relid)) AS table_size,
       pg_size_pretty(pg_indexes_size(relid)) AS indexes_size,
       ROUND(
         100.0 * pg_total_relation_size(relid)
         / NULLIF(pg_database_size(current_database()), 0),
         2
       ) AS database_percent
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(relid) DESC;

\echo === Archivos históricos ===
SELECT archive_type,
       COUNT(*) AS archive_count,
       SUM(record_count) AS archived_records,
       pg_size_pretty(SUM(size_bytes)::BIGINT) AS compressed_size,
       MIN(range_start) AS oldest_range,
       MAX(range_end) AS newest_range
FROM log_archives
GROUP BY archive_type
ORDER BY archive_type;

\echo === Registros elegibles actualmente ===
WITH policies(level, retention_days) AS (
  VALUES
    ('INFO'::log_level, 30),
    ('WARN'::log_level, 60),
    ('ERROR'::log_level, 120),
    ('CRITICAL'::log_level, 180)
)
SELECT p.level,
       p.retention_days,
       COUNT(l.id) AS eligible_records
FROM policies p
LEFT JOIN log_entries l
  ON l.level = p.level
 AND l.created_at < NOW() - make_interval(days => p.retention_days)
GROUP BY p.level, p.retention_days
ORDER BY p.retention_days;

SELECT 'MONITOR_RESULTS' AS data_type,
       90 AS retention_days,
       COUNT(*) AS eligible_records
FROM monitor_results
WHERE checked_at < NOW() - INTERVAL '90 days';

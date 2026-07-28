\pset border 2
\pset null '(null)'

\echo '=== Registros elegibles para archivo y limpieza ==='

WITH policy(level, retention_days) AS (
  VALUES
    ('INFO'::log_level, 30),
    ('WARN'::log_level, 60),
    ('ERROR'::log_level, 120),
    ('CRITICAL'::log_level, 180)
)
SELECT l.level,
       p.retention_days,
       COUNT(*) AS eligible_records,
       MIN(l.created_at) AS oldest_record,
       MAX(l.created_at) AS newest_eligible_record,
       pg_size_pretty(COALESCE(SUM(pg_column_size(l)), 0)) AS approximate_payload
FROM policy p
LEFT JOIN log_entries l
  ON l.level = p.level
 AND l.created_at < NOW() - make_interval(days => p.retention_days)
GROUP BY l.level, p.retention_days
ORDER BY p.retention_days;

\echo '=== Resultados de monitoreo elegibles (> 90 dias) ==='
SELECT COUNT(*) AS eligible_records,
       MIN(checked_at) AS oldest_record,
       MAX(checked_at) AS newest_eligible_record,
       pg_size_pretty(COALESCE(SUM(pg_column_size(monitor_results)), 0)) AS approximate_payload
FROM monitor_results
WHERE checked_at < NOW() - INTERVAL '90 days';

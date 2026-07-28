\pset border 2
\pset null '(null)'

\echo '=== Estado posterior a archivo y limpieza ==='

SELECT current_database() AS database_name,
       pg_size_pretty(pg_database_size(current_database())) AS total_size,
       pg_database_size(current_database()) AS total_bytes;

SELECT relname AS table_name,
       n_live_tup AS live_rows,
       n_dead_tup AS dead_rows,
       pg_size_pretty(pg_total_relation_size(relid)) AS total_size,
       pg_size_pretty(pg_relation_size(relid)) AS table_size,
       pg_size_pretty(pg_indexes_size(relid)) AS indexes_size,
       last_vacuum,
       last_autovacuum,
       last_analyze,
       last_autoanalyze
FROM pg_stat_user_tables
WHERE relname IN ('log_entries', 'monitor_results', 'log_archives')
ORDER BY pg_total_relation_size(relid) DESC;

\echo '=== Archivos registrados ==='
SELECT archive_type,
       file_name,
       record_count,
       pg_size_pretty(size_bytes) AS compressed_size,
       range_start,
       range_end,
       verified_at,
       created_at
FROM log_archives
ORDER BY created_at DESC
LIMIT 20;

\pset border 2
\pset null '(null)'

\echo '=== Estado de log_entries ==='
SELECT COUNT(*) AS remaining_rows,
       pg_size_pretty(pg_total_relation_size('log_entries')) AS total_size,
       pg_size_pretty(pg_relation_size('log_entries')) AS table_size,
       pg_size_pretty(pg_indexes_size('log_entries')) AS indexes_size
FROM log_entries;

\echo '=== Filas vivas y muertas estimadas ==='
SELECT relname AS table_name,
       n_live_tup AS estimated_live_rows,
       n_dead_tup AS estimated_dead_rows,
       last_vacuum,
       last_autovacuum,
       last_analyze,
       last_autoanalyze
FROM pg_stat_user_tables
WHERE relname = 'log_entries';

\echo '=== Archivos de retencion registrados ==='
SELECT id,
       file_name,
       record_count,
       pg_size_pretty(size_bytes) AS archive_size,
       range_start,
       range_end,
       verified_at,
       checksum_sha256
FROM log_archives
WHERE archive_type = 'LOG_RETENTION'
ORDER BY created_at DESC
LIMIT 10;

\echo '=== Distribucion restante por nivel ==='
SELECT level,
       COUNT(*) AS records,
       MIN(created_at) AS oldest_record,
       MAX(created_at) AS newest_record
FROM log_entries
GROUP BY level
ORDER BY level;

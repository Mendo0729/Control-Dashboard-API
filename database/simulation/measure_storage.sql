\pset border 2
\pset null '(null)'

\echo === Tamaño total de la base de datos ===
SELECT
  current_database() AS database_name,
  pg_size_pretty(pg_database_size(current_database())) AS total_size,
  pg_database_size(current_database()) AS total_bytes;

\echo === Tamaño por tabla e índices ===
SELECT
  schemaname,
  relname AS table_name,
  n_live_tup AS estimated_rows,
  pg_size_pretty(pg_total_relation_size(relid)) AS total_size,
  pg_size_pretty(pg_relation_size(relid)) AS table_size,
  pg_size_pretty(pg_indexes_size(relid)) AS indexes_size,
  pg_total_relation_size(relid) AS total_bytes
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(relid) DESC;

\echo === Promedio aproximado de bytes por registro ===
SELECT
  relname AS table_name,
  n_live_tup AS estimated_rows,
  pg_total_relation_size(relid) AS total_bytes,
  CASE
    WHEN n_live_tup > 0
      THEN ROUND(pg_total_relation_size(relid)::NUMERIC / n_live_tup, 2)
    ELSE NULL
  END AS approximate_bytes_per_row
FROM pg_stat_user_tables
ORDER BY total_bytes DESC;

\echo === Distribución de logs por nivel ===
SELECT
  level,
  COUNT(*) AS records,
  MIN(created_at) AS oldest_record,
  MAX(created_at) AS newest_record
FROM log_entries
GROUP BY level
ORDER BY records DESC;

\echo === Proyección basada en los últimos 7 días ===
WITH daily_growth AS (
  SELECT
    created_at::DATE AS day,
    COUNT(*) AS rows_created,
    SUM(pg_column_size(log_entries.*)) AS payload_bytes
  FROM log_entries
  WHERE created_at >= NOW() - INTERVAL '7 days'
  GROUP BY created_at::DATE
), averages AS (
  SELECT
    AVG(rows_created) AS average_rows_per_day,
    AVG(payload_bytes) AS average_payload_bytes_per_day
  FROM daily_growth
)
SELECT
  ROUND(average_rows_per_day, 2) AS average_rows_per_day,
  pg_size_pretty(average_payload_bytes_per_day::BIGINT) AS average_payload_per_day,
  pg_size_pretty((average_payload_bytes_per_day * 30)::BIGINT) AS projected_payload_30_days,
  pg_size_pretty((average_payload_bytes_per_day * 90)::BIGINT) AS projected_payload_90_days,
  pg_size_pretty((average_payload_bytes_per_day * 365)::BIGINT) AS projected_payload_365_days
FROM averages;

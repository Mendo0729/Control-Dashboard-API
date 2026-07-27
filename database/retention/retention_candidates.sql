\pset border 2
\pset null '(null)'

\echo '=== Candidatos de retencion por nivel ==='

WITH policy(level, retention_days) AS (
  VALUES
    ('DEBUG'::log_level, 14),
    ('INFO'::log_level, 30),
    ('WARN'::log_level, 60),
    ('ERROR'::log_level, 120),
    ('CRITICAL'::log_level, 180)
), candidates AS (
  SELECT l.level,
         p.retention_days,
         l.created_at
  FROM log_entries l
  JOIN policy p ON p.level = l.level
  WHERE l.created_at < NOW() - make_interval(days => p.retention_days)
)
SELECT level,
       retention_days,
       COUNT(*) AS candidate_rows,
       MIN(created_at) AS oldest_candidate,
       MAX(created_at) AS newest_candidate
FROM candidates
GROUP BY level, retention_days
ORDER BY retention_days;

\echo '=== Total de candidatos ==='

WITH policy(level, retention_days) AS (
  VALUES
    ('DEBUG'::log_level, 14),
    ('INFO'::log_level, 30),
    ('WARN'::log_level, 60),
    ('ERROR'::log_level, 120),
    ('CRITICAL'::log_level, 180)
)
SELECT COUNT(*) AS total_candidate_rows,
       COALESCE(pg_size_pretty(SUM(pg_column_size(l))::BIGINT), '0 bytes') AS approximate_payload
FROM log_entries l
JOIN policy p ON p.level = l.level
WHERE l.created_at < NOW() - make_interval(days => p.retention_days);

\set projects_count 10
\set days_history 30
\set logs_per_project_day 1000
\set monitor_checks_per_project_day 288

\echo Generando proyectos simulados...

INSERT INTO projects (name, slug, description, status, visibility_public)
SELECT
  'Proyecto simulado ' || n,
  'simulated-project-' || n,
  'Proyecto generado para pruebas de crecimiento.',
  CASE
    WHEN n % 10 = 0 THEN 'MAINTENANCE'::project_status
    WHEN n % 4 = 0 THEN 'DEVELOPMENT'::project_status
    ELSE 'ACTIVE'::project_status
  END,
  FALSE
FROM generate_series(1, :projects_count) AS n
ON CONFLICT (slug) DO NOTHING;

INSERT INTO monitors (project_id, name, target, interval_seconds)
SELECT
  p.id,
  'Health HTTP',
  'https://example.invalid/' || p.slug || '/health',
  300
FROM projects p
WHERE p.slug LIKE 'simulated-project-%'
ON CONFLICT (project_id, name) DO NOTHING;

\echo Generando logs simulados...

INSERT INTO log_entries (
  project_id,
  service,
  environment,
  level,
  message,
  fingerprint,
  metadata,
  first_seen_at,
  last_seen_at,
  created_at
)
SELECT
  p.id,
  CASE (entry_number % 4)
    WHEN 0 THEN 'api'
    WHEN 1 THEN 'worker'
    WHEN 2 THEN 'database-monitor'
    ELSE 'web'
  END,
  CASE WHEN entry_number % 8 = 0 THEN 'staging' ELSE 'production' END,
  CASE
    WHEN entry_number % 500 = 0 THEN 'CRITICAL'::log_level
    WHEN entry_number % 50 = 0 THEN 'ERROR'::log_level
    WHEN entry_number % 10 = 0 THEN 'WARN'::log_level
    ELSE 'INFO'::log_level
  END,
  CASE
    WHEN entry_number % 500 = 0 THEN 'Servicio no disponible durante la verificación'
    WHEN entry_number % 50 = 0 THEN 'Error controlado durante la operación simulada'
    WHEN entry_number % 10 = 0 THEN 'Latencia superior al umbral configurado'
    ELSE 'Operación completada correctamente'
  END,
  encode(digest(p.slug || ':' || (entry_number % 25)::text, 'sha256'), 'hex'),
  jsonb_build_object(
    'simulation', TRUE,
    'sequence', entry_number,
    'responseTimeMs', 20 + (entry_number % 1500)
  ),
  event_time,
  event_time,
  event_time
FROM projects p
CROSS JOIN LATERAL generate_series(
  1,
  (:days_history * :logs_per_project_day)::INTEGER
) AS entry_number
CROSS JOIN LATERAL (
  SELECT NOW()
    - (:days_history || ' days')::INTERVAL
    + (entry_number::NUMERIC / (:logs_per_project_day * :days_history))
      * (:days_history || ' days')::INTERVAL AS event_time
) generated_time
WHERE p.slug LIKE 'simulated-project-%';

\echo Generando resultados de monitoreo...

INSERT INTO monitor_results (
  monitor_id,
  status,
  status_code,
  response_time_ms,
  error_message,
  checked_at
)
SELECT
  m.id,
  CASE
    WHEN check_number % 1000 = 0 THEN 'DOWN'::monitor_status
    WHEN check_number % 100 = 0 THEN 'DEGRADED'::monitor_status
    ELSE 'UP'::monitor_status
  END,
  CASE WHEN check_number % 1000 = 0 THEN 503 ELSE 200 END,
  30 + (check_number % 1200),
  CASE WHEN check_number % 1000 = 0 THEN 'Timeout simulado' END,
  NOW()
    - (:days_history || ' days')::INTERVAL
    + (check_number::NUMERIC / (:monitor_checks_per_project_day * :days_history))
      * (:days_history || ' days')::INTERVAL
FROM monitors m
JOIN projects p ON p.id = m.project_id
CROSS JOIN LATERAL generate_series(
  1,
  (:days_history * :monitor_checks_per_project_day)::INTEGER
) AS check_number
WHERE p.slug LIKE 'simulated-project-%';

ANALYZE;

\echo Simulación terminada.

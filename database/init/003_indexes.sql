CREATE INDEX idx_sessions_user_expires
  ON user_sessions (user_id, expires_at DESC)
  WHERE revoked_at IS NULL;

CREATE INDEX idx_projects_status
  ON projects (status, updated_at DESC);

CREATE INDEX idx_repositories_project
  ON repositories (project_id, last_sync_at DESC);

CREATE INDEX idx_deployments_project_started
  ON deployments (project_id, started_at DESC);

CREATE INDEX idx_deployments_status
  ON deployments (status, started_at DESC);

CREATE INDEX idx_database_metrics_connection_collected
  ON database_metrics (database_connection_id, collected_at DESC);

CREATE INDEX idx_monitor_results_monitor_checked
  ON monitor_results (monitor_id, checked_at DESC);

CREATE INDEX idx_monitor_results_status_checked
  ON monitor_results (status, checked_at DESC);

CREATE INDEX idx_logs_project_created
  ON log_entries (project_id, created_at DESC);

CREATE INDEX idx_logs_level_created
  ON log_entries (level, created_at DESC);

CREATE INDEX idx_logs_service_environment_created
  ON log_entries (service, environment, created_at DESC);

CREATE INDEX idx_logs_fingerprint
  ON log_entries (project_id, fingerprint, last_seen_at DESC)
  WHERE fingerprint IS NOT NULL;

CREATE INDEX idx_logs_metadata_gin
  ON log_entries USING GIN (metadata jsonb_path_ops);

CREATE INDEX idx_alerts_active_severity
  ON alerts (severity, detected_at DESC)
  WHERE status <> 'RESOLVED';

CREATE INDEX idx_audit_events_entity_created
  ON audit_events (entity_type, entity_id, created_at DESC);

CREATE INDEX idx_audit_events_user_created
  ON audit_events (user_id, created_at DESC)
  WHERE user_id IS NOT NULL;

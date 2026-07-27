CREATE TYPE user_role AS ENUM ('OWNER', 'ADMIN', 'VIEWER');
CREATE TYPE project_status AS ENUM ('ACTIVE', 'DEVELOPMENT', 'MAINTENANCE', 'PAUSED', 'ARCHIVED');
CREATE TYPE log_level AS ENUM ('DEBUG', 'INFO', 'WARN', 'ERROR', 'CRITICAL');
CREATE TYPE deployment_status AS ENUM ('PENDING', 'BUILDING', 'DEPLOYING', 'SUCCESS', 'FAILED', 'ROLLED_BACK', 'CANCELLED');
CREATE TYPE monitor_status AS ENUM ('UP', 'DEGRADED', 'DOWN', 'UNKNOWN');
CREATE TYPE alert_severity AS ENUM ('INFO', 'WARNING', 'HIGH', 'CRITICAL');
CREATE TYPE alert_status AS ENUM ('ACTIVE', 'ACKNOWLEDGED', 'RESOLVED');

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(120) NOT NULL,
  email VARCHAR(255) NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  role user_role NOT NULL DEFAULT 'VIEWER',
  mfa_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  mfa_secret_encrypted TEXT,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  last_login_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK ((mfa_enabled = FALSE) OR (mfa_secret_encrypted IS NOT NULL))
);

CREATE TABLE user_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  refresh_token_hash TEXT NOT NULL,
  ip_address INET,
  user_agent TEXT,
  expires_at TIMESTAMPTZ NOT NULL,
  revoked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE mfa_recovery_codes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  code_hash TEXT NOT NULL,
  used_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE projects (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(150) NOT NULL,
  slug VARCHAR(160) NOT NULL UNIQUE,
  description TEXT,
  status project_status NOT NULL DEFAULT 'DEVELOPMENT',
  visibility_public BOOLEAN NOT NULL DEFAULT FALSE,
  production_url TEXT,
  staging_url TEXT,
  logo_url TEXT,
  featured BOOLEAN NOT NULL DEFAULT FALSE,
  created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE project_technologies (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  name VARCHAR(80) NOT NULL,
  category VARCHAR(50),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (project_id, name)
);

CREATE TABLE repositories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  provider VARCHAR(40) NOT NULL DEFAULT 'GITHUB',
  owner VARCHAR(120) NOT NULL,
  repository_name VARCHAR(180) NOT NULL,
  repository_url TEXT NOT NULL,
  default_branch VARCHAR(120) NOT NULL DEFAULT 'main',
  is_private BOOLEAN NOT NULL DEFAULT TRUE,
  last_commit_sha VARCHAR(64),
  last_commit_at TIMESTAMPTZ,
  last_sync_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (provider, owner, repository_name)
);

CREATE TABLE deployments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  repository_id UUID REFERENCES repositories(id) ON DELETE SET NULL,
  provider VARCHAR(50) NOT NULL,
  environment VARCHAR(40) NOT NULL,
  version VARCHAR(80),
  commit_sha VARCHAR(64),
  status deployment_status NOT NULL DEFAULT 'PENDING',
  deployment_url TEXT,
  started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at TIMESTAMPTZ,
  metadata JSONB NOT NULL DEFAULT '{}'::JSONB
);

CREATE TABLE database_connections (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  name VARCHAR(120) NOT NULL,
  engine VARCHAR(40) NOT NULL,
  host_encrypted TEXT NOT NULL,
  port INTEGER NOT NULL CHECK (port BETWEEN 1 AND 65535),
  database_name VARCHAR(150) NOT NULL,
  username_encrypted TEXT NOT NULL,
  password_encrypted TEXT NOT NULL,
  ssl_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  status monitor_status NOT NULL DEFAULT 'UNKNOWN',
  last_check_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (project_id, name)
);

CREATE TABLE database_metrics (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  database_connection_id UUID NOT NULL REFERENCES database_connections(id) ON DELETE CASCADE,
  status monitor_status NOT NULL,
  latency_ms INTEGER CHECK (latency_ms IS NULL OR latency_ms >= 0),
  size_bytes BIGINT CHECK (size_bytes IS NULL OR size_bytes >= 0),
  active_connections INTEGER CHECK (active_connections IS NULL OR active_connections >= 0),
  table_count INTEGER CHECK (table_count IS NULL OR table_count >= 0),
  metadata JSONB NOT NULL DEFAULT '{}'::JSONB,
  collected_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE monitors (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  name VARCHAR(120) NOT NULL,
  monitor_type VARCHAR(40) NOT NULL DEFAULT 'HTTP',
  target TEXT NOT NULL,
  interval_seconds INTEGER NOT NULL DEFAULT 300 CHECK (interval_seconds >= 60),
  timeout_seconds INTEGER NOT NULL DEFAULT 10 CHECK (timeout_seconds BETWEEN 1 AND 120),
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  expected_status_code INTEGER DEFAULT 200 CHECK (expected_status_code BETWEEN 100 AND 599),
  last_status monitor_status NOT NULL DEFAULT 'UNKNOWN',
  last_checked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (project_id, name)
);

CREATE TABLE monitor_results (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  monitor_id UUID NOT NULL REFERENCES monitors(id) ON DELETE CASCADE,
  status monitor_status NOT NULL,
  status_code INTEGER CHECK (status_code IS NULL OR status_code BETWEEN 100 AND 599),
  response_time_ms INTEGER CHECK (response_time_ms IS NULL OR response_time_ms >= 0),
  error_message TEXT,
  checked_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE log_entries (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  service VARCHAR(120) NOT NULL,
  environment VARCHAR(40) NOT NULL,
  level log_level NOT NULL,
  message TEXT NOT NULL,
  fingerprint VARCHAR(64),
  occurrence_count INTEGER NOT NULL DEFAULT 1 CHECK (occurrence_count > 0),
  metadata JSONB NOT NULL DEFAULT '{}'::JSONB,
  first_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE log_archives (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID REFERENCES projects(id) ON DELETE SET NULL,
  archive_type VARCHAR(40) NOT NULL,
  file_name TEXT NOT NULL,
  file_path TEXT NOT NULL,
  checksum_sha256 VARCHAR(64) NOT NULL,
  record_count BIGINT NOT NULL CHECK (record_count >= 0),
  range_start TIMESTAMPTZ NOT NULL,
  range_end TIMESTAMPTZ NOT NULL,
  size_bytes BIGINT NOT NULL CHECK (size_bytes >= 0),
  verified_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (range_end >= range_start)
);

CREATE TABLE alerts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
  alert_type VARCHAR(80) NOT NULL,
  severity alert_severity NOT NULL,
  status alert_status NOT NULL DEFAULT 'ACTIVE',
  title VARCHAR(200) NOT NULL,
  message TEXT NOT NULL,
  source_type VARCHAR(50),
  source_id TEXT,
  detected_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  acknowledged_at TIMESTAMPTZ,
  resolved_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE audit_events (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  action VARCHAR(100) NOT NULL,
  entity_type VARCHAR(80) NOT NULL,
  entity_id TEXT,
  ip_address INET,
  metadata JSONB NOT NULL DEFAULT '{}'::JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER users_set_updated_at
BEFORE UPDATE ON users
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER projects_set_updated_at
BEFORE UPDATE ON projects
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER repositories_set_updated_at
BEFORE UPDATE ON repositories
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER database_connections_set_updated_at
BEFORE UPDATE ON database_connections
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER monitors_set_updated_at
BEFORE UPDATE ON monitors
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER alerts_set_updated_at
BEFORE UPDATE ON alerts
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

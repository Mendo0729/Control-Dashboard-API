INSERT INTO users (name, email, password_hash, role)
VALUES ('Abdiel Mendoza', 'admin@mendotech.lat', 'LOCAL_DEVELOPMENT_ONLY', 'OWNER');

WITH owner_user AS (
  SELECT id FROM users WHERE email = 'admin@mendotech.lat'
)
INSERT INTO projects (
  name,
  slug,
  description,
  status,
  visibility_public,
  featured,
  created_by
)
SELECT
  'Control Dashboard',
  'control-dashboard',
  'Centro privado de administración y observabilidad de proyectos.',
  'DEVELOPMENT',
  FALSE,
  TRUE,
  id
FROM owner_user;

INSERT INTO project_technologies (project_id, name, category)
SELECT id, technology, category
FROM projects
CROSS JOIN (VALUES
  ('NestJS', 'Backend'),
  ('PostgreSQL', 'Database'),
  ('Prisma', 'ORM'),
  ('React', 'Frontend')
) AS technologies(technology, category)
WHERE slug = 'control-dashboard';

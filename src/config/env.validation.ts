const ALLOWED_ENVIRONMENTS = ['development', 'test', 'production'] as const;

type NodeEnvironment = (typeof ALLOWED_ENVIRONMENTS)[number];

type EnvironmentVariables = Record<string, unknown> & {
  NODE_ENV: NodeEnvironment;
  PORT: number;
  API_PREFIX: string;
  DATABASE_URL: string;
  JWT_SECRET: string;
  JWT_EXPIRES_IN_SECONDS: number;
};

function readRequiredString(
  config: Record<string, unknown>,
  key: string,
): string {
  const value = config[key];

  if (typeof value !== 'string' || value.trim() === '') {
    throw new Error(`La variable de entorno ${key} es obligatoria.`);
  }

  return value.trim();
}

function readPort(config: Record<string, unknown>): number {
  const rawPort = config.PORT ?? 3000;
  const port = Number(rawPort);

  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error('PORT debe ser un número entero entre 1 y 65535.');
  }

  return port;
}

function readJwtExpiration(config: Record<string, unknown>): number {
  const rawValue = config.JWT_EXPIRES_IN_SECONDS ?? 3600;
  const seconds = Number(rawValue);

  if (!Number.isInteger(seconds) || seconds < 60 || seconds > 604800) {
    throw new Error(
      'JWT_EXPIRES_IN_SECONDS debe ser un entero entre 60 y 604800.',
    );
  }

  return seconds;
}

function readNodeEnvironment(config: Record<string, unknown>): NodeEnvironment {
  const value = String(config.NODE_ENV ?? 'development');

  if (!ALLOWED_ENVIRONMENTS.includes(value as NodeEnvironment)) {
    throw new Error(
      `NODE_ENV debe ser uno de: ${ALLOWED_ENVIRONMENTS.join(', ')}.`,
    );
  }

  return value as NodeEnvironment;
}

function validateDatabaseUrl(databaseUrl: string): void {
  let parsedUrl: URL;

  try {
    parsedUrl = new URL(databaseUrl);
  } catch {
    throw new Error('DATABASE_URL debe ser una URL válida de PostgreSQL.');
  }

  if (!['postgresql:', 'postgres:'].includes(parsedUrl.protocol)) {
    throw new Error('DATABASE_URL debe utilizar el protocolo postgresql://.');
  }

  if (!parsedUrl.hostname || !parsedUrl.pathname.slice(1)) {
    throw new Error('DATABASE_URL debe incluir host y nombre de base de datos.');
  }
}

function validateJwtSecret(jwtSecret: string): void {
  if (jwtSecret.length < 32) {
    throw new Error('JWT_SECRET debe contener al menos 32 caracteres.');
  }
}

export function validateEnvironment(
  config: Record<string, unknown>,
): EnvironmentVariables {
  const databaseUrl = readRequiredString(config, 'DATABASE_URL');
  const jwtSecret = readRequiredString(config, 'JWT_SECRET');
  const apiPrefix = String(config.API_PREFIX ?? 'api').trim();

  if (apiPrefix === '') {
    throw new Error('API_PREFIX no puede estar vacío.');
  }

  validateDatabaseUrl(databaseUrl);
  validateJwtSecret(jwtSecret);

  return {
    ...config,
    NODE_ENV: readNodeEnvironment(config),
    PORT: readPort(config),
    API_PREFIX: apiPrefix,
    DATABASE_URL: databaseUrl,
    JWT_SECRET: jwtSecret,
    JWT_EXPIRES_IN_SECONDS: readJwtExpiration(config),
  };
}

# Control Dashboard API

Backend y entorno de datos para **Mendo Control Center**.

## Estado actual

### Base de datos

- PostgreSQL 17 mediante Docker Compose.
- modelo relacional, restricciones e índices.
- datos iniciales de desarrollo.
- simulación de crecimiento y medición de almacenamiento.
- políticas de retención.
- archivo JSON Lines comprimido con GZIP.
- checksum SHA-256 y trazabilidad en base de datos.
- eliminación segura por lotes.
- restauración de archivos históricos.

### Backend

- NestJS 11.
- configuración validada con `@nestjs/config`.
- Prisma 7 con adaptador PostgreSQL.
- health check en `GET /api/health`.
- autenticación JWT.
- inicio de sesión en `POST /api/auth/login`.
- ruta protegida en `GET /api/auth/me`.
- contraseñas verificadas con bcrypt.
- validación global de DTO.

## Roadmap

1. ✅ Base de datos y simulación.
2. ✅ NestJS.
3. ✅ Prisma.
4. ✅ Configuración.
5. ✅ Autenticación JWT.
6. 🔄 Users.
7. Projects.
8. Monitors.
9. Logs y Dashboard.
10. Swagger y pruebas.

## Requisitos

- Docker Desktop.
- Docker Compose.
- Git.
- Node.js 20 o superior.
- npm.
- PowerShell 7 o Windows PowerShell 5.1.

## Configuración inicial

Crea el archivo local de configuración:

```powershell
Copy-Item .env.example .env
```

Configura en `.env`:

```env
NODE_ENV=development
PORT=3000
API_PREFIX=api

POSTGRES_DB=control_dashboard
POSTGRES_USER=control_admin
POSTGRES_PASSWORD=replace_with_a_secure_password
POSTGRES_PORT=5433

DATABASE_URL="postgresql://control_admin:replace_with_a_secure_password@127.0.0.1:5433/control_dashboard?schema=public"

JWT_SECRET=replace_with_at_least_32_random_characters
JWT_EXPIRES_IN_SECONDS=3600
```

No subas `.env` al repositorio.

## Iniciar PostgreSQL y pgAdmin

```powershell
docker compose up -d
```

| Servicio | Dirección |
|---|---|
| PostgreSQL | `127.0.0.1:5433` |
| pgAdmin | `http://localhost:5050` |

Dentro de la red Docker, pgAdmin debe conectarse a PostgreSQL usando:

```text
Host: control-dashboard-db
Puerto: 5432
Base de datos: control_dashboard
Usuario: control_admin
```

Los scripts de `database/init` se ejecutan solamente cuando se crea el volumen de PostgreSQL por primera vez.

## Preparar y ejecutar el backend

```powershell
npm install
npx prisma generate
npm run typecheck
npm run build
npm run start:dev
```

La API queda disponible en:

```text
http://localhost:3000/api
```

Verifica el health check:

```powershell
Invoke-RestMethod http://localhost:3000/api/health
```

## Autenticación

La preparación del secreto JWT, la contraseña local del administrador y las pruebas de `login` y `me` están documentadas en:

- [Autenticación JWT](docs/authentication.md)

Rutas disponibles:

| Método | Ruta | Protección |
|---|---|---|
| `GET` | `/api/health` | Pública |
| `POST` | `/api/auth/login` | Pública |
| `GET` | `/api/auth/me` | Bearer JWT |

## Prisma

Introspección de la base de datos:

```powershell
npx prisma db pull
```

Generación del cliente:

```powershell
npx prisma generate
```

El cliente se genera en:

```text
src/generated/prisma
```

## Simulación

```powershell
Get-Content database/simulation/generate_data.sql |
  docker compose exec -T postgres psql `
    -U control_admin `
    -d control_dashboard
```

Las variables del escenario están al comienzo de `database/simulation/generate_data.sql`.

## Medición de almacenamiento

```powershell
Get-Content database/simulation/measure_storage.sql |
  docker compose exec -T postgres psql `
    -U control_admin `
    -d control_dashboard
```

Panel consolidado:

```powershell
Get-Content database/simulation/storage_dashboard.sql |
  docker compose exec -T postgres psql `
    -U control_admin `
    -d control_dashboard
```

## Política de retención

| Información | Retención local |
|---|---:|
| Logs `INFO` | 30 días |
| Logs `WARN` | 60 días |
| Logs `ERROR` | 120 días |
| Logs `CRITICAL` | 180 días |
| Resultados detallados de monitoreo | 90 días |

Vista previa:

```powershell
.\scripts\run-retention-maintenance.ps1
```

Aplicar mantenimiento:

```powershell
.\scripts\run-retention-maintenance.ps1 -Apply -BatchSize 10000
```

El proceso fija una fecha de corte, exporta, comprime, verifica, registra el archivo, elimina por lotes y ejecuta `VACUUM (ANALYZE)`.

Los archivos se guardan en `database/exports/` y no se versionan en Git.

## Validación posterior

```powershell
Get-Content database/simulation/measure_cleanup.sql |
  docker compose exec -T postgres psql `
    -U control_admin `
    -d control_dashboard
```

## Reiniciar la base local

> Este procedimiento elimina el volumen y todos los datos locales.

```powershell
docker compose down -v
docker compose up -d
```

## Estructura principal

```text
src/
├── auth/
├── config/
├── database/
├── generated/prisma/
├── app.controller.ts
├── app.module.ts
├── app.service.ts
└── main.ts

database/
├── init/
├── simulation/
└── exports/

docs/
├── architecture.md
├── authentication.md
└── maintenance.md

scripts/
├── archive-and-cleanup.ps1
├── archive-monitor-results.ps1
└── run-retention-maintenance.ps1
```

## Documentación

- [Arquitectura](docs/architecture.md)
- [Autenticación JWT](docs/authentication.md)
- [Mantenimiento y retención](docs/maintenance.md)

## Siguiente etapa

El siguiente bloque es **Users**: crear el módulo de usuarios, endpoints protegidos, DTO, control de roles y administración segura de cuentas.

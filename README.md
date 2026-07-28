# Control Dashboard API

Backend y entorno de datos para **Mendo Control Center**.

## Estado actual

La fase de datos PostgreSQL ya incluye:

- modelo relacional e índices;
- datos base y simulación de crecimiento;
- medición de almacenamiento;
- políticas de retención;
- archivo JSON Lines comprimido con GZIP;
- checksum SHA-256 y trazabilidad en base de datos;
- eliminación segura por lotes;
- mantenimiento unificado de logs y monitoreo.

La siguiente fase incorporará restauración de archivos, pruebas automáticas, CI y la aplicación NestJS/Prisma.

## Requisitos

- Docker Desktop
- Docker Compose
- Git
- PowerShell 7 o Windows PowerShell 5.1

## Inicio rápido

```powershell
Copy-Item .env.example .env
docker compose up -d
```

| Servicio | Dirección |
|---|---|
| PostgreSQL | `localhost:5432` |
| pgAdmin | `http://localhost:5050` |

Los scripts de `database/init` se ejecutan solamente cuando se crea el volumen de PostgreSQL por primera vez.

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

### Vista previa completa

```powershell
.\scripts\run-retention-maintenance.ps1
```

### Aplicar mantenimiento

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

```powershell
docker compose down -v
docker compose up -d
```

## Estructura

```text
database/
├── init/
├── simulation/
│   ├── generate_data.sql
│   ├── measure_storage.sql
│   ├── retention_preview.sql
│   ├── measure_cleanup.sql
│   └── storage_dashboard.sql
└── exports/

docs/
├── architecture.md
└── maintenance.md

scripts/
├── archive-and-cleanup.ps1
├── archive-monitor-results.ps1
└── run-retention-maintenance.ps1
```

## Documentación

- [Arquitectura](docs/architecture.md)
- [Mantenimiento y retención](docs/maintenance.md)

## Próximos pasos

1. Implementar restauración verificada de archivos.
2. Añadir pruebas automáticas del ciclo de retención.
3. Configurar GitHub Actions.
4. Registrar métricas históricas de mantenimiento.
5. Traducir el modelo aprobado a Prisma.
6. Inicializar la aplicación NestJS.

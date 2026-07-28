# Arquitectura

## Objetivo

Control Dashboard API centraliza proyectos, despliegues, monitoreo, métricas y eventos operativos. La fase actual valida el modelo PostgreSQL y el ciclo de vida de datos antes de incorporar NestJS y Prisma.

## Componentes

- PostgreSQL 17: persistencia principal.
- pgAdmin: administración local.
- Docker Compose: entorno reproducible.
- PowerShell: simulación, archivo, limpieza y restauración.
- JSON Lines + GZIP: formato de archivo histórico.

## Flujo de datos

1. Los proyectos agrupan repositorios, despliegues, conexiones y monitores.
2. `log_entries` almacena eventos de aplicación.
3. `monitor_results` almacena verificaciones detalladas.
4. Las políticas de retención identifican registros vencidos.
5. Los registros se exportan, comprimen y verifican con SHA-256.
6. `log_archives` conserva la trazabilidad del archivo.
7. La eliminación se ejecuta por lotes y termina con `VACUUM (ANALYZE)`.

## Tablas de mayor crecimiento

- `log_entries`
- `monitor_results`
- `database_metrics`
- `audit_events`

## Decisiones operativas

- No se ejecuta `VACUUM FULL` automáticamente porque requiere bloqueo exclusivo.
- Los archivos locales no se versionan en Git.
- Cada proceso fija una fecha de corte para evitar inconsistencias durante la ejecución.
- La restauración conserva los identificadores originales y omite duplicados existentes.

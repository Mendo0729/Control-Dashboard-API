# Control Dashboard API

Backend y entorno de datos para **Mendo Control Center**.

## Fase actual: base de datos local

La primera implementación valida el modelo PostgreSQL antes de iniciar NestJS y Prisma.

Objetivos:

- medir crecimiento de tablas e índices;
- simular logs y verificaciones de monitoreo;
- definir políticas de retención;
- exportar información antes de eliminarla;
- mantener el consumo dentro del límite del plan gratuito.

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

Servicios locales:

| Servicio | Dirección |
|---|---|
| PostgreSQL | `localhost:5432` |
| pgAdmin | `http://localhost:5050` |

Los scripts de `database/init` se ejecutan solamente cuando se crea el volumen de PostgreSQL por primera vez.

## Ejecutar una simulación

El generador utiliza valores predeterminados de 10 proyectos, 30 días, 1,000 logs diarios por proyecto y 288 verificaciones diarias por monitor.

```powershell
Get-Content database/simulation/generate_data.sql |
  docker compose exec -T postgres psql `
    -U control_admin `
    -d control_dashboard
```

Para modificar un escenario, edita las variables ubicadas al principio de `database/simulation/generate_data.sql`.

## Medir almacenamiento

```powershell
Get-Content database/simulation/measure_storage.sql |
  docker compose exec -T postgres psql `
    -U control_admin `
    -d control_dashboard
```

El reporte muestra:

- tamaño total de la base;
- tamaño de tablas e índices;
- promedio aproximado por registro;
- distribución de logs;
- proyección a 30, 90 y 365 días.

## Política inicial de retención

| Información | Retención local |
|---|---:|
| Logs `INFO` | 30 días |
| Logs `WARN` | 60 días |
| Logs `ERROR` | 120 días |
| Logs `CRITICAL` | 180 días |
| Resultados detallados de monitoreo | 90 días |

### Vista previa

La vista previa no exporta ni elimina información.

```powershell
Get-Content database/simulation/retention_preview.sql |
  docker compose exec -T postgres psql `
    -U control_admin `
    -d control_dashboard

.\scripts\archive-and-cleanup.ps1
```

### Aplicar archivo y limpieza

```powershell
.\scripts\archive-and-cleanup.ps1 -Apply -BatchSize 10000
```

El proceso:

1. fija una fecha de corte;
2. exporta los logs vencidos en formato JSON Lines;
3. comprime el archivo con `gzip`;
4. verifica la cantidad exportada;
5. calcula un checksum SHA-256;
6. registra el archivo en `log_archives`;
7. elimina los registros en lotes;
8. ejecuta `VACUUM (ANALYZE)`.

Los archivos se guardan en `database/exports/`. Esta carpeta está montada dentro del contenedor como `/exports`.

La limpieza normal no ejecuta `VACUUM FULL`. El espacio liberado queda disponible para reutilización interna de PostgreSQL sin bloquear completamente la tabla.

### Medir el resultado

```powershell
Get-Content database/simulation/measure_cleanup.sql |
  docker compose exec -T postgres psql `
    -U control_admin `
    -d control_dashboard
```

## Reiniciar completamente la base

Este comando elimina los datos locales y vuelve a ejecutar los scripts de inicialización:

```powershell
docker compose down -v
docker compose up -d
```

## Estructura actual

```text
database/
├── init/
│   ├── 001_extensions.sql
│   ├── 002_schema.sql
│   ├── 003_indexes.sql
│   └── 004_seed.sql
├── simulation/
│   ├── generate_data.sql
│   ├── measure_storage.sql
│   ├── retention_preview.sql
│   └── measure_cleanup.sql
└── exports/

scripts/
└── archive-and-cleanup.ps1
```

## Próximos pasos

1. Ejecutar escenarios de 90, 180 y 365 días.
2. Validar la política de retención mediante exportación y limpieza.
3. Comparar el crecimiento antes y después del mantenimiento.
4. Revisar el costo de los índices de `log_entries`.
5. Traducir el modelo aprobado a Prisma.
6. Inicializar la aplicación NestJS.

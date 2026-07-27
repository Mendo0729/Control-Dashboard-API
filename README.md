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
docker compose exec -T postgres psql `
  -U control_admin `
  -d control_dashboard `
  -f /dev/stdin < database/simulation/generate_data.sql
```

Para modificar un escenario, edita las variables ubicadas al principio de `database/simulation/generate_data.sql`.

## Medir almacenamiento

```powershell
docker compose exec -T postgres psql `
  -U control_admin `
  -d control_dashboard `
  -f /dev/stdin < database/simulation/measure_storage.sql
```

El reporte muestra:

- tamaño total de la base;
- tamaño de tablas e índices;
- promedio aproximado por registro;
- distribución de logs;
- proyección a 30, 90 y 365 días.

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
│   └── measure_storage.sql
└── exports/
```

## Próximos pasos

1. Ejecutar escenarios de crecimiento.
2. Registrar resultados por volumen.
3. Implementar exportación verificable.
4. Implementar limpieza por lotes.
5. Definir la política final de retención.
6. Traducir el modelo aprobado a Prisma.

# Control Dashboard API

Backend y entorno de datos para **Mendo Control Center**.

## Estado actual

El proyecto inicia con la definición y simulación local de PostgreSQL para validar:

- crecimiento de tablas e índices;
- retención de logs, métricas y auditoría;
- exportación antes de la limpieza;
- comportamiento dentro del límite de almacenamiento del plan gratuito.

La implementación de NestJS y Prisma se incorporará después de aprobar el modelo y los resultados de la simulación.

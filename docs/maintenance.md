# Mantenimiento y retención

## Políticas

| Datos | Retención |
|---|---:|
| Logs INFO | 30 días |
| Logs WARN | 60 días |
| Logs ERROR | 120 días |
| Logs CRITICAL | 180 días |
| Resultados de monitoreo | 90 días |

## Vista previa

```powershell
.\scripts\run-retention-maintenance.ps1
```

## Aplicación

```powershell
.\scripts\run-retention-maintenance.ps1 -Apply -BatchSize 10000
```

## Garantías

- fecha de corte fija;
- exportación previa a eliminación;
- conteo exportado validado;
- compresión GZIP;
- checksum SHA-256;
- registro en `log_archives`;
- eliminación por lotes;
- `VACUUM (ANALYZE)` al finalizar.

## Programación sugerida

Ejecutar una vez al día durante una ventana de baja actividad. En Windows puede configurarse mediante Task Scheduler y en Linux mediante cron o systemd timer.

## Recuperación de espacio

`VACUUM` permite reutilizar internamente el espacio. El tamaño físico puede no disminuir. `VACUUM FULL` debe ejecutarse únicamente durante una ventana controlada porque bloquea la tabla.

## Validación

```powershell
Get-Content database/simulation/measure_cleanup.sql |
  docker compose exec -T postgres psql `
    -U control_admin `
    -d control_dashboard
```

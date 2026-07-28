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

## Restauración

La restauración acepta el identificador registrado en `log_archives` o el nombre del archivo.

Primero ejecuta una vista previa:

```powershell
.\scripts\restore-archive.ps1 `
  -ArchiveId 18c7a6c9-8baa-49b6-8ec1-49a94d2ce063
```

También puede seleccionarse por nombre:

```powershell
.\scripts\restore-archive.ps1 `
  -FileName monitor_results_20260728_135442.jsonl.gz
```

Para aplicar la restauración:

```powershell
.\scripts\restore-archive.ps1 `
  -ArchiveId 18c7a6c9-8baa-49b6-8ec1-49a94d2ce063 `
  -Apply
```

Antes de insertar, el script:

1. consulta los metadatos en `log_archives`;
2. confirma que el archivo exista en `database/exports`;
3. verifica el checksum SHA-256;
4. valida la cantidad de líneas JSONL;
5. identifica registros existentes y restaurables;
6. inserta dentro de una transacción;
7. omite identificadores duplicados;
8. actualiza la secuencia de identidad de la tabla.

La restauración soporta archivos `LOG_RETENTION` y `MONITOR_RETENTION`.

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

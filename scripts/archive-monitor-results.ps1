[CmdletBinding()]
param(
    [switch]$Apply,
    [ValidateRange(1000, 100000)]
    [int]$BatchSize = 10000,
    [ValidateRange(1, 3650)]
    [int]$RetentionDays = 90
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$dbUser = if ($env:POSTGRES_USER) { $env:POSTGRES_USER } else { 'control_admin' }
$dbName = if ($env:POSTGRES_DB) { $env:POSTGRES_DB } else { 'control_dashboard' }
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$fileBase = "monitor_results_$timestamp.jsonl"
$containerJson = "/exports/$fileBase"
$containerGzip = "$containerJson.gz"
$hostGzip = Join-Path 'database/exports' "$fileBase.gz"

function Invoke-PsqlScalar {
    param([Parameter(Mandatory)][string]$Sql)

    $result = docker compose exec -T postgres psql `
        -U $dbUser `
        -d $dbName `
        -v ON_ERROR_STOP=1 `
        -Atqc $Sql

    if ($LASTEXITCODE -ne 0) {
        throw "psql finalizo con codigo $LASTEXITCODE."
    }

    $lines = @($result)
    if ($lines.Count -eq 0 -or $null -eq $lines[-1]) {
        return ''
    }

    return ([string]$lines[-1]).Trim()
}

Write-Host 'Revisando resultados de monitoreo vencidos...'

$cutoff = Invoke-PsqlScalar "SELECT to_char(clock_timestamp(), 'YYYY-MM-DD HH24:MI:SS.USOF');"
$eligibility = "checked_at < TIMESTAMPTZ '$cutoff' - INTERVAL '$RetentionDays days'"
$expectedCount = [long](Invoke-PsqlScalar "SELECT COUNT(*) FROM monitor_results WHERE $eligibility;")

Write-Host "Resultados elegibles: $expectedCount"
Write-Host "Retencion: $RetentionDays dias"
Write-Host "Fecha de corte: $cutoff"

if ($expectedCount -eq 0) {
    Write-Host 'No hay resultados de monitoreo vencidos.'
    exit 0
}

if (-not $Apply) {
    Write-Host 'Modo vista previa. No se exportaron ni eliminaron registros.'
    Write-Host 'Ejecuta nuevamente con -Apply para aplicar el archivo y la limpieza.'
    exit 0
}

$range = Invoke-PsqlScalar "SELECT MIN(checked_at)::text || '|' || MAX(checked_at)::text FROM monitor_results WHERE $eligibility;"
$rangeParts = $range.Split('|', 2)
$rangeStart = $rangeParts[0]
$rangeEnd = $rangeParts[1]

Write-Host "Exportando a $containerJson..."
$copySql = @"
COPY (
    SELECT row_to_json(export_row)
    FROM (
        SELECT id, monitor_id, status, status_code, response_time_ms,
               error_message, checked_at
        FROM monitor_results
        WHERE $eligibility
        ORDER BY id
    ) AS export_row
) TO '$containerJson';
"@

Invoke-PsqlScalar $copySql | Out-Null

if (-not (Test-Path (Join-Path 'database/exports' $fileBase))) {
    throw "La exportacion no genero el archivo esperado: $containerJson"
}

docker compose exec -T postgres sh -c "gzip -f '$containerJson'"
if ($LASTEXITCODE -ne 0) { throw 'No se pudo comprimir el archivo.' }

$exportedCount = [long](docker compose exec -T postgres sh -c "gzip -cd '$containerGzip' | wc -l")
if ($LASTEXITCODE -ne 0) { throw 'No se pudo verificar la cantidad exportada.' }

if ($exportedCount -ne $expectedCount) {
    throw "Verificacion fallida: se esperaban $expectedCount registros y se exportaron $exportedCount. No se eliminara informacion."
}

$checksum = (docker compose exec -T postgres sh -c "sha256sum '$containerGzip' | cut -d' ' -f1").Trim()
$sizeBytes = [long](docker compose exec -T postgres sh -c "stat -c %s '$containerGzip'")

if ($checksum -notmatch '^[a-f0-9]{64}$') {
    throw 'El checksum SHA-256 generado no es valido.'
}

Write-Host "Archivo verificado: $hostGzip"
Write-Host "SHA-256: $checksum"
Write-Host "Tamano comprimido: $sizeBytes bytes"

$archiveId = Invoke-PsqlScalar @"
INSERT INTO log_archives (
    archive_type, file_name, file_path, checksum_sha256,
    record_count, range_start, range_end, size_bytes, verified_at
)
VALUES (
    'MONITOR_RETENTION', '$fileBase.gz', '$containerGzip', '$checksum',
    $exportedCount, TIMESTAMPTZ '$rangeStart', TIMESTAMPTZ '$rangeEnd',
    $sizeBytes, NOW()
)
RETURNING id;
"@

Write-Host "Archivo registrado con ID: $archiveId"
Write-Host "Eliminando resultados en lotes de $BatchSize..."

$totalDeleted = 0L
while ($true) {
    $deleted = [long](Invoke-PsqlScalar @"
WITH batch AS (
    SELECT id
    FROM monitor_results
    WHERE $eligibility
    ORDER BY id
    LIMIT $BatchSize
), deleted AS (
    DELETE FROM monitor_results m
    USING batch b
    WHERE m.id = b.id
    RETURNING m.id
)
SELECT COUNT(*) FROM deleted;
"@)

    if ($deleted -eq 0) { break }

    $totalDeleted += $deleted
    Write-Host "Eliminados: $totalDeleted de $exportedCount"
}

if ($totalDeleted -ne $exportedCount) {
    throw "La exportacion fue registrada, pero la cantidad eliminada ($totalDeleted) no coincide con la exportada ($exportedCount)."
}

Write-Host 'Ejecutando VACUUM (ANALYZE) sobre monitor_results...'
docker compose exec -T postgres psql `
    -U $dbUser `
    -d $dbName `
    -v ON_ERROR_STOP=1 `
    -c 'VACUUM (ANALYZE) monitor_results;'
if ($LASTEXITCODE -ne 0) { throw 'VACUUM finalizo con error.' }

Write-Host 'Archivo y limpieza de resultados de monitoreo completados correctamente.'
Write-Host "Archivo local: $hostGzip"

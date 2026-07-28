[CmdletBinding()]
param(
    [ValidateRange(1, 3650)]
    [int]$DebugDays = 14,

    [ValidateRange(1, 3650)]
    [int]$InfoDays = 30,

    [ValidateRange(1, 3650)]
    [int]$WarnDays = 60,

    [ValidateRange(1, 3650)]
    [int]$ErrorDays = 120,

    [ValidateRange(1, 3650)]
    [int]$CriticalDays = 180,

    [ValidateRange(100, 100000)]
    [int]$BatchSize = 10000,

    [switch]$SkipDelete
)

$ErrorActionPreference = 'Stop'

function Invoke-PsqlScalar {
    param([Parameter(Mandatory)][string]$Sql)

    $result = docker compose exec -T postgres psql `
        -U control_admin `
        -d control_dashboard `
        -v ON_ERROR_STOP=1 `
        -At `
        -c $Sql

    if ($LASTEXITCODE -ne 0) {
        throw "psql termino con codigo $LASTEXITCODE."
    }

    return ($result | Select-Object -Last 1).Trim()
}

function Convert-ToSqlLiteral {
    param([Parameter(Mandatory)][string]$Value)
    return $Value.Replace("'", "''")
}

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$fileName = "log_entries_$timestamp.csv"
$containerPath = "/exports/$fileName"
$hostDirectory = Join-Path $PSScriptRoot '..\database\exports'
$hostDirectory = [System.IO.Path]::GetFullPath($hostDirectory)
$hostPath = Join-Path $hostDirectory $fileName

New-Item -ItemType Directory -Force -Path $hostDirectory | Out-Null

$policyPredicate = @"
(
    (level = 'DEBUG' AND created_at < NOW() - INTERVAL '$DebugDays days') OR
    (level = 'INFO' AND created_at < NOW() - INTERVAL '$InfoDays days') OR
    (level = 'WARN' AND created_at < NOW() - INTERVAL '$WarnDays days') OR
    (level = 'ERROR' AND created_at < NOW() - INTERVAL '$ErrorDays days') OR
    (level = 'CRITICAL' AND created_at < NOW() - INTERVAL '$CriticalDays days')
)
"@

$summarySql = @"
SELECT CONCAT(
    COUNT(*), '|',
    COALESCE(MIN(created_at)::TEXT, ''), '|',
    COALESCE(MAX(created_at)::TEXT, '')
)
FROM log_entries
WHERE $policyPredicate;
"@

$summary = Invoke-PsqlScalar -Sql $summarySql
$parts = $summary -split '\|', 3
$sourceCount = [int64]$parts[0]
$rangeStart = $parts[1]
$rangeEnd = $parts[2]

Write-Host "Registros candidatos: $sourceCount"

if ($sourceCount -eq 0) {
    Write-Host 'No existen registros vencidos para la politica indicada.'
    exit 0
}

$copySql = @"
COPY (
    SELECT id,
           project_id,
           service,
           environment,
           level,
           message,
           fingerprint,
           occurrence_count,
           metadata,
           first_seen_at,
           last_seen_at,
           created_at
    FROM log_entries
    WHERE $policyPredicate
    ORDER BY created_at, id
) TO '$containerPath' WITH (FORMAT CSV, HEADER TRUE, ENCODING 'UTF8');
"@

Write-Host "Exportando a $hostPath ..."
Invoke-PsqlScalar -Sql $copySql | Out-Null

if (-not (Test-Path $hostPath)) {
    throw "No se encontro el archivo exportado: $hostPath"
}

$lineCount = 0L
$reader = [System.IO.File]::OpenText($hostPath)
try {
    while ($null -ne $reader.ReadLine()) {
        $lineCount++
    }
}
finally {
    $reader.Dispose()
}

$exportedCount = [Math]::Max(0, $lineCount - 1)
if ($exportedCount -ne $sourceCount) {
    throw "Verificacion fallida. Base=$sourceCount, CSV=$exportedCount. No se eliminara informacion."
}

$fileInfo = Get-Item $hostPath
$checksum = (Get-FileHash -Path $hostPath -Algorithm SHA256).Hash.ToLowerInvariant()

$escapedFileName = Convert-ToSqlLiteral $fileName
$escapedContainerPath = Convert-ToSqlLiteral $containerPath
$escapedChecksum = Convert-ToSqlLiteral $checksum
$escapedRangeStart = Convert-ToSqlLiteral $rangeStart
$escapedRangeEnd = Convert-ToSqlLiteral $rangeEnd

$registerSql = @"
INSERT INTO log_archives (
    archive_type,
    file_name,
    file_path,
    checksum_sha256,
    record_count,
    range_start,
    range_end,
    size_bytes,
    verified_at
)
VALUES (
    'LOG_RETENTION',
    '$escapedFileName',
    '$escapedContainerPath',
    '$escapedChecksum',
    $sourceCount,
    '$escapedRangeStart'::TIMESTAMPTZ,
    '$escapedRangeEnd'::TIMESTAMPTZ,
    $($fileInfo.Length),
    NOW()
)
RETURNING id;
"@

$archiveId = Invoke-PsqlScalar -Sql $registerSql

Write-Host "Archivo verificado: $exportedCount registros"
Write-Host "SHA-256: $checksum"
Write-Host "Archivo registrado con ID: $archiveId"

if ($SkipDelete) {
    Write-Host 'SkipDelete activo: no se eliminaron registros.'
    exit 0
}

$totalDeleted = 0L
Write-Host "Eliminando en lotes de $BatchSize ..."

do {
    $deleteSql = @"
WITH doomed AS (
    SELECT ctid
    FROM log_entries
    WHERE $policyPredicate
    ORDER BY created_at, id
    LIMIT $BatchSize
), deleted AS (
    DELETE FROM log_entries l
    USING doomed d
    WHERE l.ctid = d.ctid
    RETURNING 1
)
SELECT COUNT(*) FROM deleted;
"@

    $deleted = [int64](Invoke-PsqlScalar -Sql $deleteSql)
    $totalDeleted += $deleted
    Write-Host "Eliminados: $totalDeleted / $sourceCount"
} while ($deleted -gt 0)

if ($totalDeleted -ne $sourceCount) {
    Write-Warning "La cantidad eliminada ($totalDeleted) difiere de la exportada ($sourceCount). Revise inserciones concurrentes o cambios en los datos."
}

Invoke-PsqlScalar -Sql 'VACUUM (ANALYZE) log_entries;' | Out-Null

Write-Host 'Proceso terminado.'
Write-Host "Exportados: $sourceCount"
Write-Host "Eliminados: $totalDeleted"
Write-Host 'VACUUM (ANALYZE) ejecutado. El espacio queda disponible para reutilizacion interna.'

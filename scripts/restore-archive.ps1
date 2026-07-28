[CmdletBinding(DefaultParameterSetName = 'ById')]
param(
    [Parameter(Mandatory, ParameterSetName = 'ById')]
    [ValidatePattern('^[0-9a-fA-F-]{36}$')]
    [string]$ArchiveId,

    [Parameter(Mandatory, ParameterSetName = 'ByFile')]
    [ValidatePattern('^[A-Za-z0-9._-]+\.jsonl\.gz$')]
    [string]$FileName,

    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$dbUser = if ($env:POSTGRES_USER) { $env:POSTGRES_USER } else { 'control_admin' }
$dbName = if ($env:POSTGRES_DB) { $env:POSTGRES_DB } else { 'control_dashboard' }

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

$where = if ($PSCmdlet.ParameterSetName -eq 'ById') {
    "id = '$ArchiveId'::uuid"
} else {
    "file_name = '$FileName'"
}

$metadata = Invoke-PsqlScalar @"
SELECT archive_type || '|' || file_name || '|' || file_path || '|' ||
       checksum_sha256 || '|' || record_count::text
FROM log_archives
WHERE $where
ORDER BY created_at DESC
LIMIT 1;
"@

if ([string]::IsNullOrWhiteSpace($metadata)) {
    throw 'No se encontro el archivo solicitado en log_archives.'
}

$parts = $metadata.Split('|', 5)
$archiveType = $parts[0]
$archiveFile = $parts[1]
$containerPath = $parts[2]
$expectedChecksum = $parts[3]
$expectedCount = [long]$parts[4]

if ($archiveFile -notmatch '^[A-Za-z0-9._-]+\.jsonl\.gz$') {
    throw "Nombre de archivo no valido: $archiveFile"
}

if ($containerPath -ne "/exports/$archiveFile") {
    throw "Ruta de archivo inesperada: $containerPath"
}

$hostPath = Join-Path 'database/exports' $archiveFile
if (-not (Test-Path $hostPath)) {
    throw "No existe el archivo local: $hostPath"
}

Write-Host "Archivo: $archiveFile"
Write-Host "Tipo: $archiveType"
Write-Host "Registros esperados: $expectedCount"

$actualChecksum = (docker compose exec -T postgres sh -c "sha256sum '$containerPath' | cut -d' ' -f1").Trim()
if ($LASTEXITCODE -ne 0) { throw 'No se pudo calcular el checksum del archivo.' }

if ($actualChecksum -ne $expectedChecksum) {
    throw "Checksum invalido. Esperado: $expectedChecksum. Actual: $actualChecksum"
}

$actualCount = [long](docker compose exec -T postgres sh -c "gzip -cd '$containerPath' | wc -l")
if ($LASTEXITCODE -ne 0) { throw 'No se pudo contar el contenido del archivo.' }

if ($actualCount -ne $expectedCount) {
    throw "Cantidad invalida. Esperada: $expectedCount. Actual: $actualCount"
}

Write-Host 'Checksum SHA-256 verificado.'
Write-Host 'Cantidad de registros verificada.'

switch ($archiveType) {
    'LOG_RETENTION' {
        $targetTable = 'log_entries'
        $jsonColumns = @"
            (payload->>'id')::bigint,
            (payload->>'project_id')::uuid,
            payload->>'service',
            payload->>'environment',
            (payload->>'level')::log_level,
            payload->>'message',
            NULLIF(payload->>'fingerprint', ''),
            (payload->>'occurrence_count')::integer,
            COALESCE(payload->'metadata', '{}'::jsonb),
            (payload->>'first_seen_at')::timestamptz,
            (payload->>'last_seen_at')::timestamptz,
            (payload->>'created_at')::timestamptz
"@
        $insertColumns = 'id, project_id, service, environment, level, message, fingerprint, occurrence_count, metadata, first_seen_at, last_seen_at, created_at'
    }
    'MONITOR_RETENTION' {
        $targetTable = 'monitor_results'
        $jsonColumns = @"
            (payload->>'id')::bigint,
            (payload->>'monitor_id')::uuid,
            (payload->>'status')::monitor_status,
            NULLIF(payload->>'status_code', '')::integer,
            NULLIF(payload->>'response_time_ms', '')::integer,
            NULLIF(payload->>'error_message', ''),
            (payload->>'checked_at')::timestamptz
"@
        $insertColumns = 'id, monitor_id, status, status_code, response_time_ms, error_message, checked_at'
    }
    default {
        throw "Tipo de archivo no soportado: $archiveType"
    }
}

$previewSql = @"
CREATE TEMP TABLE restore_raw(line text);
COPY restore_raw(line) FROM PROGRAM 'gzip -cd ''$containerPath''';
WITH parsed AS (
    SELECT line::jsonb AS payload FROM restore_raw
)
SELECT COUNT(*) FILTER (WHERE existing.id IS NULL)::text || '|' ||
       COUNT(*) FILTER (WHERE existing.id IS NOT NULL)::text
FROM parsed p
LEFT JOIN $targetTable existing
  ON existing.id = (p.payload->>'id')::bigint;
"@

$preview = Invoke-PsqlScalar $previewSql
$previewParts = $preview.Split('|', 2)
$insertable = [long]$previewParts[0]
$existing = [long]$previewParts[1]

Write-Host "Registros disponibles para restaurar: $insertable"
Write-Host "Registros ya existentes: $existing"

if (-not $Apply) {
    Write-Host 'Modo vista previa. No se insertaron registros.'
    Write-Host 'Ejecuta nuevamente con -Apply para restaurar el archivo.'
    exit 0
}

$applySql = @"
BEGIN;
CREATE TEMP TABLE restore_raw(line text) ON COMMIT DROP;
COPY restore_raw(line) FROM PROGRAM 'gzip -cd ''$containerPath''';
WITH parsed AS (
    SELECT line::jsonb AS payload FROM restore_raw
), inserted AS (
    INSERT INTO $targetTable ($insertColumns)
    SELECT
$jsonColumns
    FROM parsed
    ON CONFLICT (id) DO NOTHING
    RETURNING id
)
SELECT COUNT(*) FROM inserted;
COMMIT;
"@

$insertedCount = [long](Invoke-PsqlScalar $applySql)

if ($insertedCount -ne $insertable) {
    throw "La restauracion inserto $insertedCount registros, pero se esperaban $insertable."
}

if ($targetTable -eq 'log_entries') {
    Invoke-PsqlScalar "SELECT setval(pg_get_serial_sequence('log_entries','id'), GREATEST((SELECT COALESCE(MAX(id), 1) FROM log_entries), 1), true);" | Out-Null
} else {
    Invoke-PsqlScalar "SELECT setval(pg_get_serial_sequence('monitor_results','id'), GREATEST((SELECT COALESCE(MAX(id), 1) FROM monitor_results), 1), true);" | Out-Null
}

Write-Host "Restauracion completada. Registros insertados: $insertedCount"
Write-Host "Registros omitidos por existir previamente: $existing"

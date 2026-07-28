[CmdletBinding()]
param(
    [switch]$Apply,
    [ValidateRange(1000, 100000)]
    [int]$BatchSize = 10000,
    [ValidateRange(1, 3650)]
    [int]$MonitorRetentionDays = 90
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$logScript = Join-Path $scriptDirectory 'archive-and-cleanup.ps1'
$monitorScript = Join-Path $scriptDirectory 'archive-monitor-results.ps1'

foreach ($requiredScript in @($logScript, $monitorScript)) {
    if (-not (Test-Path $requiredScript)) {
        throw "No se encontro el script requerido: $requiredScript"
    }
}

$commonArguments = @{
    BatchSize = $BatchSize
}

if ($Apply) {
    $commonArguments.Apply = $true
}

Write-Host '=== Mantenimiento de retencion ==='
Write-Host "Modo: $(if ($Apply) { 'APLICAR' } else { 'VISTA PREVIA' })"
Write-Host "Tamano de lote: $BatchSize"

Write-Host ''
Write-Host '--- Logs ---'
& $logScript @commonArguments
if ($LASTEXITCODE -ne 0) {
    throw "El mantenimiento de logs finalizo con codigo $LASTEXITCODE."
}

Write-Host ''
Write-Host '--- Resultados de monitoreo ---'
$monitorArguments = @{
    BatchSize = $BatchSize
    RetentionDays = $MonitorRetentionDays
}
if ($Apply) {
    $monitorArguments.Apply = $true
}

& $monitorScript @monitorArguments
if ($LASTEXITCODE -ne 0) {
    throw "El mantenimiento de resultados de monitoreo finalizo con codigo $LASTEXITCODE."
}

Write-Host ''
Write-Host 'Mantenimiento de retencion completado correctamente.'

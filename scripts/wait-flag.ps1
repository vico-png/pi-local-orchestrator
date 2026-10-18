# Blocking wait for a phase flag file.
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File wait-flag.ps1 -ProjectDir "C:\proj" -Tag 7 [-TimeoutMinutes 60]
# Prints DONE (exit 0) when .orchestration/state/phase_<Tag>.flag exists,
# TIMEOUT (exit 2) after the deadline. Idempotent: safe to re-run.
param(
  [Parameter(Mandatory=$true)][string]$ProjectDir,
  [Parameter(Mandatory=$true)][string]$Tag,
  [int]$TimeoutMinutes = 60
)
$ErrorActionPreference = 'Stop'

$flag = Join-Path $ProjectDir ".orchestration/state/phase_$Tag.flag"
if (Test-Path -LiteralPath $flag) { Write-Output 'DONE'; exit 0 }

$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
while ((Get-Date) -lt $deadline) {
  if (Test-Path -LiteralPath $flag) { Write-Output 'DONE'; exit 0 }
  Start-Sleep -Seconds 20
}
Write-Output 'TIMEOUT'
exit 2

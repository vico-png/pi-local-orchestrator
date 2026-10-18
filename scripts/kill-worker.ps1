# Kills the worker window (powershell + its pi child) for a finished phase.
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File kill-worker.ps1 -ProjectDir "C:\proj" -Tag 7
param(
  [Parameter(Mandatory=$true)][string]$ProjectDir,
  [Parameter(Mandatory=$true)][string]$Tag
)
$ErrorActionPreference = 'Stop'

$pidFile = Join-Path $ProjectDir ".orchestration/state/phase_$Tag.pid"
if (-not (Test-Path -LiteralPath $pidFile)) { Write-Output 'NOPID'; exit 0 }

$procId = [int](Get-Content -LiteralPath $pidFile -Raw).Trim()
try {
  taskkill /PID $procId /T /F 2>&1 | Out-Null
  if ($LASTEXITCODE -eq 0) { Write-Output "KILLED $procId" }
  else { Write-Output "ALREADY-GONE $procId" }
} catch {
  Write-Output "ALREADY-GONE $procId"
}
Remove-Item -LiteralPath $pidFile -ErrorAction SilentlyContinue

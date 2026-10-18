# Kills the orchestrator window (powershell + its pi child + whole tree).
# Intended use: the orchestrator session kills ITSELF as its very last action.
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File kill-orchestrator.ps1 -ProjectDir "C:\proj"
param(
  [Parameter(Mandatory=$true)][string]$ProjectDir
)
$ErrorActionPreference = 'Stop'

$pidFile = Join-Path $ProjectDir ".orchestration/state/orchestrator.pid"
if (-not (Test-Path -LiteralPath $pidFile)) { Write-Output 'NOPID'; exit 0 }

$procId = [int](Get-Content -LiteralPath $pidFile -Raw).Trim()
# /T kills the whole tree (window + pi + any pending bash tool). This script's
# own process is inside that tree, so it may die before printing: that's fine.
taskkill /PID $procId /T /F 2>&1 | Out-Null
Remove-Item -LiteralPath $pidFile -ErrorAction SilentlyContinue

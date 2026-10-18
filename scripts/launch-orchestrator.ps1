# Opens a VISIBLE powershell window running the MAIN orchestrator pi session.
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File launch-orchestrator.ps1 -ProjectDir "C:\proj"
# Runs pi in INTERACTIVE TUI mode with the orchestrator prompt as a @file
# argument: the TUI auto-sends that prompt at startup. The window runs in the
# project directory. Prints the window PID and saves it to
# .orchestration/state/orchestrator.pid
param(
  [Parameter(Mandatory=$true)][string]$ProjectDir
)
$ErrorActionPreference = 'Stop'

$orch = Join-Path $ProjectDir '.orchestration'
$state = Join-Path $orch 'state'
New-Item -ItemType Directory -Force -Path $state | Out-Null

$orchFile = Join-Path $orch 'orchestrator.md'
if (-not (Test-Path -LiteralPath $orchFile)) {
  Write-Error "Orchestrator prompt not found: $orchFile (la sesion de plan debe crearlo antes de lanzar)"
  exit 1
}

# Generate a wrapper script (avoids all shell-quoting issues). Any $variable
# that must reach the wrapper LITERALLY must be backtick-escaped in this
# expandable here-string.
$wrapper = Join-Path $state 'orchestrator.ps1'
$wrapperContent = @"
Write-Host "=== Orquestador: arrancando sesion pi (TUI interactivo, todo visible) ==="
Write-Host "    (esta ventana es el agente principal de la orquestacion; no la cierres)"
pi -a "@$orchFile"
Write-Host "=== Orquestador: pi ha terminado. ==="
"@
Set-Content -LiteralPath $wrapper -Value $wrapperContent -Encoding UTF8

$proc = Start-Process -FilePath 'powershell' `
  -ArgumentList @('-NoProfile', '-NoExit', '-File', $wrapper) `
  -WorkingDirectory $ProjectDir `
  -PassThru

# Save PID (kill-orchestrator.ps1 needs it). The orchestrator window is the
# long-lived one: it stays open for the whole orchestration.
$proc.Id | Out-File -LiteralPath (Join-Path $state "orchestrator.pid") -Encoding utf8
Write-Output $proc.Id

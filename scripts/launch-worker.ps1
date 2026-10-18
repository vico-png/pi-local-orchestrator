# Launches one orchestration phase in a VISIBLE powershell window.
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File launch-worker.ps1 -ProjectDir "C:\proj" -Tag 7
#   (retry of same phase: -Tag "7_r2")
# The worker runs pi in INTERACTIVE TUI mode (no -p) with the phase prompt as
# a @file argument: the TUI auto-sends that prompt at startup, so the user sees
# everything live (streaming, tool calls, errors, loops) exactly like a normal
# pi session. Prints the window PID and saves it to .orchestration/state/phase_<Tag>.pid
param(
  [Parameter(Mandatory=$true)][string]$ProjectDir,
  [Parameter(Mandatory=$true)][string]$Tag
)
$ErrorActionPreference = 'Stop'

$orch = Join-Path $ProjectDir '.orchestration'
$state = Join-Path $orch 'state'
New-Item -ItemType Directory -Force -Path $state | Out-Null

$promptFile = Join-Path $orch "prompts/phase_$Tag.md"
if (-not (Test-Path -LiteralPath $promptFile)) {
  Write-Error "Prompt file not found: $promptFile"
  exit 1
}

# Generate a wrapper script (avoids all shell-quoting issues with the prompt).
$wrapper = Join-Path $state "worker_$Tag.ps1"
$wrapperContent = @"
Write-Host "=== Fase $Tag : iniciando worker (TUI interactivo, todo visible en esta ventana) ==="
Write-Host "    (no teclees aqui; si pi falla o entra en bucle, Ctrl+C o pide al orquestrador que mate la fase)"
pi -a "@$promptFile"
Write-Host "=== Fase $Tag : pi ha terminado. La ventana la cerrara el orquestrador. ==="
"@
Set-Content -LiteralPath $wrapper -Value $wrapperContent -Encoding UTF8

$proc = Start-Process -FilePath 'powershell' `
  -ArgumentList @('-NoProfile', '-NoExit', '-File', $wrapper) `
  -WorkingDirectory $ProjectDir `
  -PassThru

# Save PID (kill-worker.ps1 needs it). Note: with -NoExit the powershell stays
# alive after pi (TUI) ends, so window-alive != worker-alive. The flag is truth.
$proc.Id | Out-File -LiteralPath (Join-Path $state "phase_$Tag.pid") -Encoding utf8
Write-Output $proc.Id

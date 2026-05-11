# Refresh bearer token for MCP tool authentication.
#
# Thin wrapper around .vscode/scripts/refresh-bearer-token.py.
# All real logic (MSAL, on-disk DPAPI-encrypted cache, fast-path, env file
# update) lives in the Python script — much cleaner than C#-in-PowerShell.
#
# The Deploy task chain calls this on every F5; it exits in <1s when the
# existing token still has >5 min remaining.

$ErrorActionPreference = 'Stop'

$workspace = Get-Location
$python = Join-Path $workspace '.venv\Scripts\python.exe'
$script = Join-Path $workspace '.vscode\scripts\refresh-bearer-token.py'

if (-not (Test-Path $python)) {
    throw "Python venv not found at $python. Run scripts/setup-environment.ps1 first."
}
if (-not (Test-Path $script)) {
    throw "Helper script not found: $script"
}

& $python $script
exit $LASTEXITCODE

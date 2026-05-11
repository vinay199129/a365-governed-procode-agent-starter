# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

<#
.SYNOPSIS
    Acquires an Agent 365 Observability S2S bearer token and writes it to
    env/.env.playground.user as SECRET_OBS_S2S_TOKEN.

.DESCRIPTION
    The Observability exporter needs a token carrying the
    `Agent365.Observability.OtelWrite` app role on the Agent365Observability
    resource (appId 9b975845-388f-4429-889e-eab1ef63949c).

    Blueprint ("agentic") apps are not permitted to use the raw
    client-credentials flow (AADSTS82001), so for local-dev Playground mode
    we use the CLIENT APP identity instead:

      1. Ensure the client app SP (CLIENT_APP_ID) has the
         Agent365.Observability.OtelWrite app role assigned on the
         Agent365Observability resource SP.
      2. Create a client secret on the client app and store it as
         SECRET_CLIENT_APP_SECRET in env/.env.playground.user.
      3. This script uses MSAL client-credentials to acquire a token for the
         scope https://api.powerplatform.com/.default and writes it as
         SECRET_OBS_S2S_TOKEN in env/.env.playground.user.

    Known limitation: even with the OtelWrite role assigned in Entra, Power
    Platform may still issue tokens with empty `roles` until the role is
    granted/consented at the Power Platform layer for the tenant. In that
    case the exporter logs HTTP 403 (correlation ID present) but the rest of
    the pipeline (span generation, identity propagation, payload encoding)
    is fully exercised. See docs/troubleshooting.md.

    Requires: PowerShell 7+, Python venv with msal.

.EXAMPLE
    pwsh -NoProfile -File scripts/refresh-observability-token.ps1
#>

param(
    [string]$ConfigDir = (Split-Path $PSScriptRoot -Parent),
    # The observability endpoint expects a token issued for the Power Platform
    # audience (https://api.powerplatform.com) AND carrying the
    # `Agent365.Observability.OtelWrite` role claim. Power Platform is
    # supposed to enrich the token with that role from the Entra
    # appRoleAssignment + admin consent (`a365 setup admin`). In tenants where
    # Frontier Preview enrollment / M365 E7 license has not propagated, the
    # `roles` claim comes back empty and the endpoint returns HTTP 403 even
    # though all client-side wiring is correct. Issuing against the resource
    # scope (`9b975845.../.default`) populates `roles` but produces the wrong
    # audience and the endpoint returns HTTP 401. See docs/troubleshooting.md.
    [string]$Scope = "https://api.powerplatform.com/.default"
)

$ErrorActionPreference = "Stop"


$configPath      = Join-Path $ConfigDir "a365.config.json"
$generatedPath   = Join-Path $ConfigDir "a365.generated.config.json"
$envPlayground   = Join-Path $ConfigDir "env/.env.playground"
$envUserPath     = Join-Path $ConfigDir "env/.env.playground.user"

if (-not (Test-Path $configPath))    { Write-Error "a365.config.json not found. Run scripts/setup-environment.ps1 first."; exit 1 }
if (-not (Test-Path $generatedPath)) { Write-Error "a365.generated.config.json not found. Run scripts/setup-environment.ps1 first."; exit 1 }
if (-not (Test-Path $envUserPath))   { Write-Error "$envUserPath not found."; exit 1 }

$config    = Get-Content $configPath    | ConvertFrom-Json
$envPgText = Get-Content $envPlayground -Raw

$TenantId = $config.tenantId

# Client app id is stored in env/.env.playground as CLIENT_APP_ID=...
if ($envPgText -notmatch '(?m)^CLIENT_APP_ID=([0-9a-fA-F-]+)') {
    Write-Error "CLIENT_APP_ID not found in $envPlayground."
    exit 1
}
$ClientAppId = $Matches[1]

# Client secret is stored in env/.env.playground.user as SECRET_CLIENT_APP_SECRET=...
# (created via scripts/setup-environment.ps1 or scripts/assign-observability-role.ps1)
$envUserText = Get-Content $envUserPath -Raw
if ($envUserText -notmatch '(?m)^SECRET_CLIENT_APP_SECRET=([^\r\n]+)') {
    Write-Error @"
SECRET_CLIENT_APP_SECRET not found in $envUserPath.

The client app needs a secret to acquire an S2S token for observability.
Run:
    az ad app credential reset --id $ClientAppId --display-name local-dev-observability --years 1 --append --output json

Then add SECRET_CLIENT_APP_SECRET=<password> to env/.env.playground.user.
"@
    exit 1
}
$ClientSecret = $Matches[1].Trim()

Write-Host "Tenant:     $TenantId"
Write-Host "Client app: $ClientAppId"
Write-Host "Scope:      $Scope"

# ---- Acquire S2S token via MSAL client credentials ----
$venvPython = Join-Path $ConfigDir ".venv/Scripts/python.exe"
if (-not (Test-Path $venvPython)) { Write-Error ".venv Python not found. Run 'uv venv' + 'uv pip install -e .' first."; exit 1 }

$py = @"
import json, sys, msal
app = msal.ConfidentialClientApplication(
    client_id=r'''$ClientAppId''',
    authority=r'''https://login.microsoftonline.com/$TenantId''',
    client_credential=r'''$ClientSecret''',
)
result = app.acquire_token_for_client(scopes=[r'''$Scope'''])
if 'access_token' not in result:
    print(json.dumps(result), file=sys.stderr)
    sys.exit(1)
print(result['access_token'])
"@

$tokenFile = Join-Path $env:TEMP ("a365-obs-token-" + [guid]::NewGuid().ToString() + ".txt")
try {
    $py | & $venvPython -c "import sys; exec(sys.stdin.read())" 2>&1 | Tee-Object -FilePath $tokenFile | Out-Null
    $lines = Get-Content $tokenFile
    $token = ($lines | Where-Object { $_ -and $_.Trim() -ne "" } | Select-Object -Last 1)
    if (-not $token -or $token -match "^\{") {
        Write-Error "Token acquisition failed:`n$($lines -join "`n")"
        exit 1
    }
} finally {
    if (Test-Path $tokenFile) { Remove-Item $tokenFile -Force -ErrorAction SilentlyContinue }
}

Write-Host "Token acquired successfully (length: $($token.Length) chars)"

# ---- Write SECRET_OBS_S2S_TOKEN into env/.env.playground.user ----
$content = Get-Content $envUserPath -Raw
if ($content -match '(?m)^SECRET_OBS_S2S_TOKEN=.*$') {
    $content = $content -replace '(?m)^SECRET_OBS_S2S_TOKEN=.*$', "SECRET_OBS_S2S_TOKEN=$token"
} else {
    $content = $content.TrimEnd() + "`nSECRET_OBS_S2S_TOKEN=$token`n"
}
Set-Content -Path $envUserPath -Value $content.TrimEnd() -Encoding UTF8
Write-Host "SECRET_OBS_S2S_TOKEN updated in $envUserPath"

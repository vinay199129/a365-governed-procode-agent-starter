# Refresh bearer token for MCP tool authentication (no WAM)
# Run with: pwsh -NoProfile -File .vscode/scripts/refresh-bearer-token.ps1
#
# This script bypasses the unreliable Windows Account Manager (WAM) used by
# the a365 CLI. It acquires a token using MSAL.NET device code flow, which
# works reliably in VS Code terminals without hidden popup issues.
#
# Auth strategy (in order):
#   1. MSAL.NET device code flow via Microsoft.Identity.Client (primary)
#      - Uses the MSAL DLL bundled with Microsoft.Graph.Authentication module
#      - Displays a code + URL in the terminal for browser sign-in
#      - No hidden popups, no WAM dependency
#
# Requires: PowerShell 7+, Microsoft.Graph.Authentication module (for MSAL DLL)

$ErrorActionPreference = 'Stop'

$workspace = Get-Location
$playgroundEnvPath = Join-Path $workspace 'env/.env.playground'
$playgroundUserEnvPath = Join-Path $workspace 'env/.env.playground.user'
$configPath = Join-Path $workspace 'a365.config.json'
$manifestPath = Join-Path $workspace 'ToolingManifest.json'

# --- Validate prerequisites ---
if (-not (Test-Path $playgroundEnvPath)) { throw "Missing env file: $playgroundEnvPath" }
if (-not (Test-Path $configPath)) { throw "Missing config: $configPath. Run a365 config init first." }
if (-not (Test-Path $manifestPath)) { throw "Missing manifest: $manifestPath" }

# --- Read configuration ---
$config = Get-Content $configPath -Raw | ConvertFrom-Json
$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
$TenantId = $config.tenantId

$appIdLine = Get-Content $playgroundEnvPath | Where-Object { $_ -match '^\s*CLIENT_APP_ID\s*=' } | Select-Object -First 1
if (-not $appIdLine) { throw "CLIENT_APP_ID not found in $playgroundEnvPath" }
$ClientAppId = ($appIdLine -split '=', 2)[1].Trim()
if ([string]::IsNullOrWhiteSpace($ClientAppId)) { throw "CLIENT_APP_ID is empty in $playgroundEnvPath" }

# --- Build scopes from ToolingManifest.json ---
$resourceAppId = $manifest.mcpServers[0].audience
$rawScopes = $manifest.mcpServers | ForEach-Object { $_.scope } | Select-Object -Unique
$msalScopes = @($rawScopes | ForEach-Object { "$resourceAppId/$_" })

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Bearer Token Refresh (device code flow, no WAM)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Tenant:     $TenantId"
Write-Host "  Client App: $ClientAppId"
Write-Host "  Resource:   $resourceAppId"
Write-Host "  Scopes:     $($rawScopes -join ', ')"
Write-Host ""

# --- Ensure a365 CLI permissions are configured ---
$a365Command = Get-Command a365 -ErrorAction SilentlyContinue
if ($a365Command) {
    Write-Host "Ensuring MCP permissions on client app..." -ForegroundColor Yellow
    & a365 develop add-permissions --app-id $ClientAppId 2>&1 | Out-Null
}

# --- Load MSAL.NET from Microsoft.Graph.Authentication module ---
Write-Host ""
Write-Host "Loading MSAL library..." -ForegroundColor Yellow

$msalAssembly = [System.AppDomain]::CurrentDomain.GetAssemblies() |
    Where-Object { $_.GetName().Name -eq 'Microsoft.Identity.Client' } |
    Select-Object -First 1

if (-not $msalAssembly) {
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
    $graphModulePath = (Get-Module Microsoft.Graph.Authentication).ModuleBase
    # MSAL DLL lives under Dependencies/Desktop (Windows) or Dependencies/Core
    $msalPath = Join-Path $graphModulePath 'Dependencies' 'Desktop' 'Microsoft.Identity.Client.dll'
    if (-not (Test-Path $msalPath)) {
        $msalPath = Join-Path $graphModulePath 'Dependencies' 'Core' 'Microsoft.Identity.Client.dll'
    }
    if (-not (Test-Path $msalPath)) {
        $msalPath = Join-Path $graphModulePath 'Dependencies' 'Microsoft.Identity.Client.dll'
    }
    if (-not (Test-Path $msalPath)) {
        throw "Cannot find Microsoft.Identity.Client.dll. Ensure Microsoft.Graph.Authentication module is installed: Install-Module Microsoft.Graph.Authentication -Scope CurrentUser"
    }
    Add-Type -Path $msalPath
}

# --- Build MSAL public client app ---
$authority = "https://login.microsoftonline.com/$TenantId"

$publicApp = [Microsoft.Identity.Client.PublicClientApplicationBuilder]::Create($ClientAppId).
    WithAuthority($authority).
    WithRedirectUri("http://localhost").
    Build()

# Build .NET typed scope list
$scopeList = [System.Collections.Generic.List[string]]::new()
foreach ($s in $msalScopes) { $scopeList.Add($s) }

# --- Try silent auth first (cached token), then device code ---
$bearerToken = $null

try {
    $accounts = $publicApp.GetAccountsAsync().GetAwaiter().GetResult()
    $firstAccount = $accounts | Select-Object -First 1
    if ($firstAccount) {
        Write-Host "Attempting silent token acquisition (cached)..." -ForegroundColor Yellow
        $result = $publicApp.AcquireTokenSilent($scopeList, $firstAccount).ExecuteAsync().GetAwaiter().GetResult()
        $bearerToken = $result.AccessToken
        Write-Host "Token acquired from cache." -ForegroundColor Green
    } else {
        throw "No cached account — need interactive auth"
    }
} catch {
    # Silent failed — use device code flow
    Write-Host "Using device code flow for authentication..." -ForegroundColor Yellow
    Write-Host ""

    # Callback must be pure .NET (no PowerShell runspace on MSAL's thread)
    $csCode = @"
using System;
using System.Threading.Tasks;
using Microsoft.Identity.Client;
public static class DeviceCodeHelper {
    public static Task Callback(DeviceCodeResult dcr) {
        Console.ForegroundColor = ConsoleColor.Cyan;
        Console.WriteLine("------------------------------------------------------------");
        Console.WriteLine(dcr.Message);
        Console.WriteLine("------------------------------------------------------------");
        Console.ResetColor();
        Console.WriteLine();
        return Task.CompletedTask;
    }
}
"@
    Add-Type -ReferencedAssemblies @($msalPath, 'System.Console', 'System.Runtime') -TypeDefinition $csCode

    $callback = [Func[Microsoft.Identity.Client.DeviceCodeResult, System.Threading.Tasks.Task]]([DeviceCodeHelper]::Callback)
    $result = $publicApp.AcquireTokenWithDeviceCode($scopeList, $callback).ExecuteAsync().GetAwaiter().GetResult()

    $bearerToken = $result.AccessToken
}

if ([string]::IsNullOrWhiteSpace($bearerToken)) {
    throw "Failed to acquire bearer token"
}

Write-Host ""
Write-Host "Token acquired successfully (length: $($bearerToken.Length) chars)" -ForegroundColor Green

# --- Update .env.playground.user ---
$userEnvLines = @()
if (Test-Path $playgroundUserEnvPath) {
    $userEnvLines = @(Get-Content $playgroundUserEnvPath)
}

$updated = $false
for ($i = 0; $i -lt $userEnvLines.Count; $i++) {
    if ($userEnvLines[$i] -match '^\s*SECRET_BEARER_TOKEN\s*=') {
        $userEnvLines[$i] = "SECRET_BEARER_TOKEN=$bearerToken"
        $updated = $true
        break
    }
}

if (-not $updated) {
    if ($userEnvLines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($userEnvLines[-1])) {
        $userEnvLines += ''
    }
    $userEnvLines += "SECRET_BEARER_TOKEN=$bearerToken"
}

Set-Content -Path $playgroundUserEnvPath -Value $userEnvLines -Encoding UTF8
Write-Host "SECRET_BEARER_TOKEN updated in env/.env.playground.user" -ForegroundColor Green

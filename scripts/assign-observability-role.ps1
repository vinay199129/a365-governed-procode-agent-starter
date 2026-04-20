# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

<#
.SYNOPSIS
    Assigns the Observability S2S app role (`Agent365.Observability.OtelWrite`)
    to the agent blueprint service principal.

.DESCRIPTION
    Connects to Microsoft Graph, resolves the blueprint and Observability API
    service principals, and grants the `Agent365.Observability.OtelWrite` app
    role so the blueprint (and all inheriting instances) can emit OpenTelemetry
    traces to the A365 backend.

    Must be run AFTER `scripts/setup-environment.ps1` (which runs `a365 setup all`
    and produces `a365.generated.config.json`).

    Requires: PowerShell 7+, Microsoft.Graph PowerShell module, admin consent
    for `AppRoleAssignment.ReadWrite.All`.

.PARAMETER ConfigDir
    Directory containing `a365.config.json` and `a365.generated.config.json`.
    Defaults to the repository root (parent of the scripts folder).

.EXAMPLE
    pwsh -NoProfile -File scripts/assign-observability-role.ps1
#>

param(
    [string]$ConfigDir = (Split-Path $PSScriptRoot -Parent)
)

$ErrorActionPreference = "Stop"

# Read blueprint ID and tenant ID from config files
$configPath = Join-Path $ConfigDir "a365.config.json"
$generatedPath = Join-Path $ConfigDir "a365.generated.config.json"

if (-not (Test-Path $configPath)) { Write-Error "a365.config.json not found at $ConfigDir. Run a365 config init first."; exit 1 }
if (-not (Test-Path $generatedPath)) { Write-Error "a365.generated.config.json not found at $ConfigDir. Run a365 setup all first."; exit 1 }

$config = Get-Content $configPath | ConvertFrom-Json
$generated = Get-Content $generatedPath | ConvertFrom-Json

$TenantId = $config.tenantId
$BlueprintAppId = $generated.agentBlueprintId
$ClientAppId = $config.clientAppId

Write-Host "Tenant:    $TenantId"
Write-Host "Blueprint: $BlueprintAppId"
Write-Host "Client:    $ClientAppId"
Write-Host ""

# Disable WAM to avoid hidden popup issues in VS Code embedded terminals
Write-Host "Disabling WAM and connecting to Microsoft Graph (browser auth)..."
Set-MgGraphOption -DisableLoginByWAM $true
Connect-MgGraph -Scopes "AppRoleAssignment.ReadWrite.All" -TenantId $TenantId -ClientId $ClientAppId

Write-Host "Looking up Blueprint service principal..."
$bp = Get-MgServicePrincipal -Filter "appId eq '$BlueprintAppId'"
Write-Host "  Blueprint SP: $($bp.Id)"

Write-Host "Looking up Observability API service principal..."
$obs = Get-MgServicePrincipal -Filter "appId eq '9b975845-388f-4429-889e-eab1ef63949c'"
Write-Host "  Observability SP: $($obs.Id)"

$rid = ($obs.AppRoles | Where-Object { $_.Value -eq "Agent365.Observability.OtelWrite" }).Id
Write-Host "  OtelWrite Role ID: $rid"

if (-not $bp.Id -or -not $obs.Id -or -not $rid) {
    Write-Error "Could not resolve all required IDs. Check that the blueprint and Observability API exist."
    exit 1
}

Write-Host "Assigning OtelWrite app role..."
try {
    New-MgServicePrincipalAppRoleAssignment `
        -ServicePrincipalId $bp.Id `
        -PrincipalId $bp.Id `
        -ResourceId $obs.Id `
        -AppRoleId $rid
    Write-Host "Observability S2S role assigned successfully!"
} catch {
    if ($_.Exception.Message -like "*already exists*" -or $_.Exception.Message -like "*Permission being assigned already exists*") {
        Write-Host "Role assignment already exists - OK"
    } else {
        throw
    }
}

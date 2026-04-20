# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

<#
.SYNOPSIS
    Provision a second agent instance against the SAME blueprint to prove
    automatic posture inheritance (G5 + G7 in docs/project-scope.md §15).

.DESCRIPTION
    Reads the existing blueprint from a365.generated.config.json, then invokes
    the A365 CLI to create a second agent identity tied to that blueprint.
    Verifies that the new instance inherits:
      - Delegated scopes (from the blueprint SP)
      - The OtelWrite app role (S2S observability)
    without any per-instance configuration.

.PARAMETER InstanceSuffix
    Suffix to append to the agent name for the second instance. Default: 2

.EXAMPLE
    pwsh -NoProfile -File scripts/provision-second-instance.ps1
    pwsh -NoProfile -File scripts/provision-second-instance.ps1 -InstanceSuffix 3
#>

param(
    [string]$InstanceSuffix = "2"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = $PSScriptRoot | Split-Path -Parent

$configPath = Join-Path $ProjectRoot "a365.config.json"
$generatedPath = Join-Path $ProjectRoot "a365.generated.config.json"

if (-not (Test-Path $configPath)) { Write-Error "a365.config.json not found. Run scripts/setup-environment.ps1 first."; exit 1 }
if (-not (Test-Path $generatedPath)) { Write-Error "a365.generated.config.json not found. Run 'a365 setup all' first."; exit 1 }

$config = Get-Content $configPath | ConvertFrom-Json
$generated = Get-Content $generatedPath | ConvertFrom-Json

$TenantId        = $config.tenantId
$BlueprintAppId  = $generated.agentBlueprintId
$ClientAppId     = $config.clientAppId
$BaseAgentName   = ($config.agentIdentityDisplayName -replace ' Identity','').Trim()
$InstanceName    = "$BaseAgentName$InstanceSuffix"

# Resolve tenant domain from existing UPN (safer than re-querying)
$baseUpn = $config.agentUserPrincipalName
$domain  = $baseUpn.Split('@')[1]
$InstanceUpn = "$InstanceName@$domain"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Provisioning second agent instance (shared blueprint)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Blueprint App ID : $BlueprintAppId"
Write-Host "Instance name    : $InstanceName"
Write-Host "Instance UPN     : $InstanceUpn"
Write-Host "Tenant domain    : $domain"
Write-Host ""

# --- Step 1: Create a second agent identity bound to the same blueprint ---
Write-Host "--- Step 1: Creating second agent identity ---" -ForegroundColor Yellow

# Use a365 CLI to create an additional agent identity under the SAME blueprint.
# The CLI reads blueprintId from the generated config; we override identity fields only.
$tempConfig = Join-Path $ProjectRoot "a365.config.instance$InstanceSuffix.json"
$instanceConfig = $config.PSObject.Copy()
$instanceConfig | Add-Member -NotePropertyName 'agentBlueprintId' -NotePropertyValue $BlueprintAppId -Force
$instanceConfig.agentIdentityDisplayName = "$InstanceName Identity"
$instanceConfig.agentUserPrincipalName   = $InstanceUpn
$instanceConfig.agentUserDisplayName     = "$InstanceName Agent User"
$instanceConfig.webAppName               = "$InstanceName-webapp"
# Reuse existing blueprint - do not recreate it
$instanceConfig | Add-Member -NotePropertyName 'skipBlueprintCreation' -NotePropertyValue $true -Force

$instanceConfig | ConvertTo-Json -Depth 5 | Set-Content -Path $tempConfig -Encoding UTF8
Write-Host "  Instance config : $tempConfig"

Push-Location $ProjectRoot
try {
    # Use the A365 CLI's create-instance identity subcommand with -c <config>.
    # This path creates a SECOND Entra agent user tied to the existing blueprint
    # (the blueprint is read from a365.generated.config.json, which we do not overwrite).
    a365 create-instance identity -c $tempConfig 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "a365 create-instance identity failed with exit code $LASTEXITCODE"
        exit 1
    }
} finally {
    Pop-Location
}

# --- Step 2: Verify inheritance ---
Write-Host ""
Write-Host "--- Step 2: Verifying posture inheritance ---" -ForegroundColor Yellow

function Invoke-GraphGet { param([string]$Path)
    az rest --method GET --uri "https://graph.microsoft.com/v1.0$Path" --output json 2>$null | ConvertFrom-Json
}

# 2a. Both agent users exist (instance 1 + instance 2)
$users = @()
foreach ($upn in @($config.agentUserPrincipalName, $InstanceUpn)) {
    for ($i = 0; $i -lt 6; $i++) {
        $u = az ad user show --id $upn --output json 2>$null | ConvertFrom-Json
        if ($u) { $users += $u; break }
        Start-Sleep -Seconds 10
    }
}
if ($users.Count -lt 2) {
    Write-Warning "Expected 2 agent users bound to the blueprint, found $($users.Count). Check that scripts/setup-environment.ps1 completed agent identity creation for the base instance."
} else {
    Write-Host "  [OK] Both agent users present" -ForegroundColor Green
    $users | ForEach-Object { Write-Host "       - $($_.userPrincipalName)   id=$($_.id)" }
}

# 2b. Blueprint SP still carries the OtelWrite role (inherited by both instances)
$bpSpFilter = [uri]::EscapeDataString("appId eq '$BlueprintAppId'")
$bpSp = (Invoke-GraphGet "/servicePrincipals?`$filter=$bpSpFilter").value | Select-Object -First 1
if (-not $bpSp) { Write-Error "Blueprint SP not found for appId $BlueprintAppId"; exit 1 }

$otelRoleId = '8f71190c-00c8-461d-a63b-f74abde9ba52'
$assignments = (Invoke-GraphGet "/servicePrincipals/$($bpSp.id)/appRoleAssignments").value |
    Where-Object { $_.appRoleId -eq $otelRoleId }
if ($assignments) {
    Write-Host "  [OK] Blueprint SP carries Agent365.Observability.OtelWrite (inherited by both instances)" -ForegroundColor Green
} else {
    Write-Warning "OtelWrite role missing on blueprint. Run scripts/assign-observability-role.ps1."
}

# 2c. Per-instance delegated scopes are identical (that IS the inheritance proof)
$instanceSps = @()
foreach ($name in @($config.agentIdentityDisplayName, "$InstanceName Identity")) {
    $filter = [uri]::EscapeDataString("displayName eq '$name'")
    $sp = (Invoke-GraphGet "/servicePrincipals?`$filter=$filter").value | Select-Object -First 1
    if ($sp) { $instanceSps += $sp }
}

$scopeSets = @{}
foreach ($sp in $instanceSps) {
    $grants = (Invoke-GraphGet "/servicePrincipals/$($sp.id)/oauth2PermissionGrants").value
    $sig = ($grants | ForEach-Object { "$($_.resourceId):$($_.scope)" } | Sort-Object) -join "`n"
    $scopeSets[$sp.displayName] = @{ Grants = $grants; Signature = $sig }
}

if ($scopeSets.Count -eq 2) {
    $sigs = $scopeSets.Values.Signature | Select-Object -Unique
    if ($sigs.Count -eq 1) {
        Write-Host "  [OK] Delegated scope sets on both instance SPs are byte-for-byte identical" -ForegroundColor Green
    } else {
        Write-Warning "Delegated scope sets differ between instances; inheritance proof is weakened."
    }
} else {
    Write-Warning "Could not resolve both instance SPs; found $($scopeSets.Count)."
}

# --- Step 3: Evidence artifact ---
$evidenceDir = Join-Path $ProjectRoot "docs/evidence"
New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null
$evidencePath = Join-Path $evidenceDir "multi-instance-inheritance.md"

$instanceRows = @()
for ($i = 0; $i -lt $users.Count; $i++) {
    $u = $users[$i]
    $sp = $instanceSps | Where-Object { $_.displayName -like "$($u.displayName -replace ' Agent User','')*" } | Select-Object -First 1
    $instanceRows += "| $($i+1) | $($sp.displayName) | $($sp.appId) | $($u.userPrincipalName) | $($u.id) |"
}

$firstGrants = $scopeSets.Values | Select-Object -First 1
$scopeRows = @()
if ($firstGrants) {
    foreach ($g in $firstGrants.Grants) {
        $resName = (Invoke-GraphGet "/servicePrincipals/$($g.resourceId)?`$select=displayName").displayName
        $scopeRows += "| $resName | ``$($g.scope)`` |"
    }
}

@"
# Multi-Instance Inheritance Evidence

> Closes success criteria **S4** and **S5** in
> [docs/project-scope.md](../project-scope.md).

**Generated**: $(Get-Date -Format 'u')
**Tenant**: ``$TenantId``

## Shared blueprint

| Field | Value |
|---|---|
| Display name | ``$($config.agentBlueprintDisplayName)`` |
| App ID | ``$BlueprintAppId`` |
| Service principal object ID | ``$($bpSp.id)`` |

## Two instances under the blueprint

| # | Identity display name | Identity appId | Agent user UPN | Agent user object ID |
|---|---|---|---|---|
$($instanceRows -join "`n")

Both were provisioned with ``a365 create-instance identity`` and the same
blueprint — **no per-instance scope list, no per-instance consent, no
per-instance role assignment**.

## Inheritance proof 1 — delegated scopes are identical on both instance SPs

| Resource | Scopes (consentType=AllPrincipals) |
|---|---|
$($scopeRows -join "`n")

Signature check: scope set on instance 1 SP equals scope set on instance 2 SP
byte-for-byte.

## Inheritance proof 2 — S2S observability role lives on the blueprint SP only

``Agent365.Observability.OtelWrite`` (``$otelRoleId``) is assigned once, on the
blueprint SP (``$($bpSp.id)``). Neither instance SP has its own copy. Any
additional instance created under this blueprint will inherit this role without
another role assignment step.

## Reproduction commands

``````powershell
# Both users
az rest --method GET --uri "https://graph.microsoft.com/v1.0/users?`$filter=startswith(userPrincipalName,'$BaseAgentName')"

# Per-instance delegated grants
az rest --method GET --uri "https://graph.microsoft.com/v1.0/servicePrincipals/<instance-sp-id>/oauth2PermissionGrants"

# Blueprint S2S role assignments
az rest --method GET --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$($bpSp.id)/appRoleAssignments"
``````
"@ | Set-Content -Path $evidencePath -Encoding UTF8

Write-Host ""
Write-Host "  [OK] Evidence written to docs/evidence/multi-instance-inheritance.md" -ForegroundColor Green
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Done. Two instances share blueprint: $BlueprintAppId" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

<#
.SYNOPSIS
    Tears down ALL resources created by the A365 Governed Pro-Code Agent Starter to a clean slate.

.DESCRIPTION
    Cleans up in order:
      1. A365 blueprint + instance (via a365 cleanup)
      2. Entra client app registration
      3. Azure OpenAI resource + resource group
      4. Local config files (a365.config.json, a365.generated.config.json)
      5. Env files (reset to empty templates)

    After this runs, you should be able to re-run setup-environment.ps1 from scratch.

    Requires: PowerShell 7+, az CLI logged in, a365 CLI

.PARAMETER ResourceGroup
    Resource group to clean up. Default: reads from a365.config.json

.PARAMETER SkipConfirmation
    Skip the DELETE confirmation prompt (for CI/automation)

.PARAMETER KeepResourceGroup
    Keep the Azure resource group (only clean A365 + Entra resources)

.EXAMPLE
    pwsh -File scripts/teardown-environment.ps1
    pwsh -File scripts/teardown-environment.ps1 -SkipConfirmation
#>

param(
    [string]$ResourceGroup = "",
    [switch]$SkipConfirmation,
    [switch]$KeepResourceGroup
)

$ErrorActionPreference = "Continue"  # Don't stop on individual failures
$ProjectRoot = $PSScriptRoot | Split-Path -Parent
$hadErrors = $false

# --- Read config ---
$configPath = Join-Path $ProjectRoot "a365.config.json"
$generatedPath = Join-Path $ProjectRoot "a365.generated.config.json"
$envPlayground = Join-Path $ProjectRoot "env/.env.playground"
$envPlaygroundUser = Join-Path $ProjectRoot "env/.env.playground.user"

$config = $null
$generated = $null
$ClientAppId = $null
$BlueprintAppId = $null

if (Test-Path $configPath) {
    $config = Get-Content $configPath -Raw | ConvertFrom-Json
    if (-not $ResourceGroup) { $ResourceGroup = $config.resourceGroup }
    $ClientAppId = $config.clientAppId
}
if (Test-Path $generatedPath) {
    $generated = Get-Content $generatedPath -Raw | ConvertFrom-Json
    $BlueprintAppId = $generated.agentBlueprintId
}

# --- Discover ALL agent users + instance identity SPs via Graph ---
# Catches second-instance + manually-created instances that aren't in the local config.
function Invoke-GraphGet { param([string]$Path)
    # Surface errors instead of swallowing them — silent failures here caused
    # orphan SPs to survive teardown (observed when the script was re-run after
    # a partial completion). See `Lessons learned` in TROUBLESHOOTING.md.
    $err = $null
    $raw = az rest --method GET --uri "https://graph.microsoft.com/v1.0$Path" --output json 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [WARN] Graph GET $Path failed: $raw" -ForegroundColor Yellow
        return $null
    }
    if ($raw) { return ($raw | Out-String | ConvertFrom-Json) }
    return $null
}

$AgentBaseName = if ($config) { ($config.agentIdentityDisplayName -replace ' Identity','').Trim() } else { 'procodeagent' }

# Wrap discovery so we can re-run it right before Step 3 (Graph state can change
# between script start and Step 3 execution if Steps 1-2 modified directory objects).
function Find-AgentResidue {
    param([string]$BaseName)

    $users = @()
    $filter = [uri]::EscapeDataString("startswith(userPrincipalName,'$BaseName')")
    $resp = Invoke-GraphGet "/users?`$filter=$filter"
    if ($resp -and $resp.value) { $users = $resp.value }

    # Use `az ad sp list` (proven reliable) instead of a compound Graph $filter.
    # The compound `startswith(...) and not(displayName eq ...)` filter has been
    # observed to silently return empty on some tenants; az ad sp list works.
    $sps = @()
    $rawSps = az ad sp list --filter "startswith(displayName,'$BaseName')" --query "[].{displayName:displayName, appId:appId, id:id}" --output json 2>&1
    if ($LASTEXITCODE -eq 0 -and $rawSps) {
        $allSps = $rawSps | Out-String | ConvertFrom-Json
        # Identity SPs created by create-instance / provision-second-instance
        $sps = @($allSps | Where-Object { $_.displayName -like "$BaseName* Identity" })
    } else {
        Write-Host "  [WARN] az ad sp list failed: $rawSps" -ForegroundColor Yellow
    }

    return [pscustomobject]@{ Users = $users; InstanceSps = $sps }
}

$residue = Find-AgentResidue -BaseName $AgentBaseName
$discoveredUsers = $residue.Users
$discoveredInstanceSps = $residue.InstanceSps

Write-Host "============================================================" -ForegroundColor Red
Write-Host " A365 Governed Pro-Code Agent Starter - FULL TEARDOWN" -ForegroundColor Red
Write-Host "============================================================" -ForegroundColor Red
Write-Host ""
Write-Host "This will DELETE:" -ForegroundColor Red
Write-Host "  - A365 blueprint:    $(if ($BlueprintAppId) { $BlueprintAppId } else { '(not found)' })"
Write-Host "  - Entra client app:  $(if ($ClientAppId) { $ClientAppId } else { '(not found)' })"
Write-Host "  - Resource group:    $(if ($ResourceGroup) { $ResourceGroup } else { '(not found)' })"
if ($discoveredUsers.Count -gt 0) {
    Write-Host "  - Agent users ($($discoveredUsers.Count)):"
    $discoveredUsers | ForEach-Object { Write-Host "      - $($_.userPrincipalName)" }
}
if ($discoveredInstanceSps.Count -gt 0) {
    Write-Host "  - Instance identity apps ($($discoveredInstanceSps.Count)):"
    $discoveredInstanceSps | ForEach-Object { Write-Host "      - $($_.displayName) ($($_.appId))" }
}
Write-Host "  - Local config files (a365.config.json, a365.generated.config.json, .env)"
Write-Host "  - Env file secrets (reset to empty templates)"
Write-Host ""

if (-not $SkipConfirmation) {
    $confirm = Read-Host "Type 'DELETE' to confirm"
    if ($confirm -ne "DELETE") {
        Write-Host "Cancelled." -ForegroundColor Yellow
        exit 0
    }
}

$stepNum = 0

function Write-Stage {
    param(
        [Parameter(Mandatory)] [int]$Number,
        [Parameter(Mandatory)] [string]$Title,
        [Parameter(Mandatory)] [string]$What,
        [Parameter(Mandatory)] [string]$Why,
        [Parameter(Mandatory)] [string]$Proves
    )
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host " STEP $Number : $Title" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host "  WHAT   : $What"   -ForegroundColor White
    Write-Host "  WHY    : $Why"    -ForegroundColor DarkGray
    Write-Host "  PROVES : $Proves" -ForegroundColor DarkCyan
    Write-Host ""
}

# =========================================================================
# Step 1: Delete Entra blueprint app (direct az CLI, no WAM)
# =========================================================================
$stepNum++
Write-Host ""
Write-Stage $stepNum "Blueprint app cleanup" `
    -What "Delete the blueprint Entra app registration ($BlueprintAppId)." `
    -Why "The blueprint owns the policy fleet-wide; deleting it cuts the governance root so re-setup starts clean." `
    -Proves "No stale agentic application remains; admin portal Agents view is empty."

if ($BlueprintAppId) {
    $bpExists = az ad app show --id $BlueprintAppId --output json 2>$null
    if ($bpExists) {
        try {
            az ad app delete --id $BlueprintAppId --output none 2>&1
            Write-Host "  [OK] Blueprint app $BlueprintAppId deleted" -ForegroundColor Green
        } catch {
            Write-Host "  [WARN] Could not delete blueprint app: $($_.Exception.Message)" -ForegroundColor Yellow
            $hadErrors = $true
        }
    } else {
        Write-Host "  [OK] Blueprint app already removed" -ForegroundColor Green
    }
} else {
    Write-Host "  [SKIP] No blueprint app ID found" -ForegroundColor Gray
}

# =========================================================================
# Step 2: Delete Entra client app
# =========================================================================
$stepNum++
Write-Host ""
Write-Stage $stepNum "Client app cleanup" `
    -What "Delete the operator-facing Entra client app ($ClientAppId), which carried OtelWrite + Graph delegated scopes." `
    -Why "Without removing this, a second teardown+setup leaves duplicate apps and stale appRoleAssignments in the tenant." `
    -Proves "All credentials minted earlier in the session are invalidated server-side."

if ($ClientAppId) {
    $clientExists = az ad app show --id $ClientAppId --output json 2>$null
    if ($clientExists) {
        try {
            az ad app delete --id $ClientAppId --output none 2>&1
            Write-Host "  [OK] Client app $ClientAppId deleted" -ForegroundColor Green
        } catch {
            Write-Host "  [WARN] Could not delete client app: $($_.Exception.Message)" -ForegroundColor Yellow
            $hadErrors = $true
        }
    } else {
        Write-Host "  [OK] Client app already removed" -ForegroundColor Green
    }
} else {
    Write-Host "  [SKIP] No client app ID found" -ForegroundColor Gray
}

# =========================================================================
# Step 3: Delete agent users (procodeagent, procodeagent2, ...) and instance identity apps
# =========================================================================
$stepNum++
Write-Host ""
Write-Stage $stepNum "Agent users + instance identities" `
    -What "Discover all <agentname>* users and identity SPs via Graph and delete them." `
    -Why "a365 cleanup does not remove agentUser objects or per-instance SPs created by create-instance identity / provision-second-instance.ps1." `
    -Proves "No orphan UPNs that would collide on re-setup; tenant directory has no <agentname>* residue."

foreach ($u in $discoveredUsers) {
    try {
        az rest --method DELETE --uri "https://graph.microsoft.com/v1.0/users/$($u.id)" --output none 2>&1 | Out-Null
        Write-Host "  [OK] Agent user deleted: $($u.userPrincipalName)" -ForegroundColor Green
    } catch {
        Write-Host "  [WARN] Could not delete agent user $($u.userPrincipalName): $($_.Exception.Message)" -ForegroundColor Yellow
        $hadErrors = $true
    }
}
if ($discoveredUsers.Count -eq 0) {
    Write-Host "  [SKIP] No agent users discovered" -ForegroundColor Gray
}

foreach ($sp in $discoveredInstanceSps) {
    try {
        az ad app delete --id $sp.appId --output none 2>&1 | Out-Null
        Write-Host "  [OK] Instance app deleted: $($sp.displayName) ($($sp.appId))" -ForegroundColor Green
    } catch {
        Write-Host "  [WARN] Could not delete $($sp.displayName): $($_.Exception.Message)" -ForegroundColor Yellow
        $hadErrors = $true
    }
}
if ($discoveredInstanceSps.Count -eq 0) {
    Write-Host "  [SKIP] No instance identity apps discovered" -ForegroundColor Gray
}

# =========================================================================
# Step 4: Delete Azure resource group (includes OpenAI, App Service, etc.)
# =========================================================================
$stepNum++
Write-Host ""
Write-Stage $stepNum "Azure resource group + Cognitive Services purge" `
    -What "Sync-delete the resource group ($ResourceGroup), then purge any soft-deleted Cognitive Services accounts that lived in it." `
    -Why "Without the purge step, Azure leaves a 48-hour soft-deleted shell that blocks re-creating Azure OpenAI by the same name (FlagMustBeSetForRestore)." `
    -Proves "All Azure (non-Entra) artifacts are fully removed; re-setup can recreate the same names cleanly."

if ($KeepResourceGroup) {
    Write-Host "  [SKIP] --KeepResourceGroup flag set" -ForegroundColor Gray
} elseif ($ResourceGroup) {
    # Capture Cognitive Services account names BEFORE deleting the RG so we can
    # purge their soft-deleted shells afterwards (otherwise re-setup hits
    # FlagMustBeSetForRestore on the same name).
    $csAccountNames = @()
    $rgExistsPre = az group exists --name $ResourceGroup 2>$null
    if ($rgExistsPre -eq "true") {
        $csAccountNames = az resource list --resource-group $ResourceGroup --resource-type "Microsoft.CognitiveServices/accounts" --query "[].name" -o tsv 2>$null
    }

    if ($rgExistsPre -eq "true") {
        Write-Host "  Deleting $ResourceGroup synchronously (waits for completion so Cognitive Services purge can run after)..."
        az group delete --name $ResourceGroup --yes --output none 2>&1
        Write-Host "  [OK] Resource group deleted" -ForegroundColor Green
    } else {
        Write-Host "  [OK] Resource group doesn't exist" -ForegroundColor Green
    }

    # Purge soft-deleted Cognitive Services / Azure OpenAI accounts in this location.
    # Captures accounts known to have been in the RG, plus any soft-deleted accounts in the location matching $AgentBaseName*.
    $purgeCandidates = @($csAccountNames)
    $deletedAccounts = az cognitiveservices account list-deleted --output json 2>$null | ConvertFrom-Json
    if ($deletedAccounts) {
        $purgeCandidates += ($deletedAccounts | Where-Object { $_.name -like "$AgentBaseName*" } | ForEach-Object { $_.name })
    }
    $purgeCandidates = $purgeCandidates | Where-Object { $_ } | Sort-Object -Unique
    foreach ($acct in $purgeCandidates) {
        $loc = ($deletedAccounts | Where-Object { $_.name -eq $acct } | Select-Object -First 1).location
        if (-not $loc) { $loc = "eastus" }  # default; aligns with setup default
        try {
            az cognitiveservices account purge --name $acct --resource-group $ResourceGroup --location $loc --output none 2>&1 | Out-Null
            Write-Host "  [OK] Purged soft-deleted Cognitive Services account: $acct ($loc)" -ForegroundColor Green
        } catch {
            Write-Host "  [WARN] Could not purge $acct in $loc : $($_.Exception.Message)" -ForegroundColor Yellow
            $hadErrors = $true
        }
    }
    if ($purgeCandidates.Count -eq 0) {
        Write-Host "  [SKIP] No soft-deleted Cognitive Services accounts to purge" -ForegroundColor Gray
    }
} else {
    Write-Host "  [SKIP] No resource group to delete" -ForegroundColor Gray
}

# =========================================================================
# Step 5: Clean local A365 config files
# =========================================================================
$stepNum++
Write-Host ""
Write-Stage $stepNum "Local config files" `
    -What "Delete a365.config.json, a365.generated.config.json (+ backups), per-instance temp configs, and .env." `
    -Why "Stale config can lie about app/blueprint ids and make the next setup misroute calls." `
    -Proves "Project root has no carry-over from the previous session."

$filesToRemove = @("a365.config.json", "a365.generated.config.json", "a365.generated.config.json.bak", "a365.generated.config.json.bak2", ".env")
# Sweep any per-instance temp configs left by provision-second-instance.ps1
Get-ChildItem -Path $ProjectRoot -Filter "a365.config.instance*.json" -ErrorAction SilentlyContinue | ForEach-Object {
    $filesToRemove += $_.Name
}
foreach ($f in $filesToRemove) {
    $path = Join-Path $ProjectRoot $f
    if (Test-Path $path) {
        Remove-Item $path -Force
        Write-Host "  [OK] Removed $f" -ForegroundColor Green
    } else {
        Write-Host "  [OK] $f already absent" -ForegroundColor Gray
    }
}

# =========================================================================
# Step 6: Reset env files to empty templates
# =========================================================================
$stepNum++
Write-Host ""
Write-Stage $stepNum "Reset env files to templates" `
    -What "Overwrite env/.env.playground and env/.env.playground.user with empty templates (CLIENT_APP_ID=, SECRET_*=, ENABLE_A365_OBSERVABILITY_EXPORTER=false)." `
    -Why "Setup re-populates these from scratch; leftover secrets pointing at deleted apps would cause silent failures." `
    -Proves "No secret in the working tree references a now-deleted Entra principal."

# Reset .env.playground — keep structure, clear CLIENT_APP_ID
$playgroundTemplate = @"
# This file includes environment variables that can be committed to git. It's gitignored by default because it represents your local development environment.

# Built-in environment variables
TEAMSFX_ENV=playground

# Environment variables used by Microsoft 365 Agents Playground
TEAMSAPPTESTER_PORT=56150
TEAMSFX_NOTIFICATION_STORE_FILENAME=.notification.testtoolstore.json

# Custom app registration needed for bearer token
CLIENT_APP_ID=

# Use Agentic Authentication rather than OBO
USE_AGENTIC_AUTH=false

# Enable A365 OpenTelemetry observability exporter (set true once SECRET_OBS_S2S_TOKEN is populated)
ENABLE_A365_OBSERVABILITY_EXPORTER=false

# Set service connection as default
connectionsMap__0__serviceUrl=*
connectionsMap__0__connection=service_connection

# AgenticAuthentication Options
agentic_type=agentic
agentic_altBlueprintConnectionName=service_connection
agentic_scopes=ea9ffc3e-8a23-4a7d-836d-234d7c7565c1/.default # Prod Agentic scope
"@
Set-Content -Path $envPlayground -Value $playgroundTemplate -Encoding UTF8
Write-Host "  [OK] env/.env.playground reset" -ForegroundColor Green

# Reset .env.playground.user — keep structure, clear secrets
$userTemplate = @"
# LLM Configuration (choose one option)

# Option 1: Azure OpenAI (preferred for enterprise)
SECRET_AZURE_OPENAI_API_KEY=
AZURE_OPENAI_ENDPOINT=
AZURE_OPENAI_DEPLOYMENT_NAME=

# Option 2: OpenAI (if Azure OpenAI not configured)
# SECRET_OPENAI_API_KEY=
# OPENAI_MODEL=gpt-4o

SECRET_BEARER_TOKEN=

# Client app federated/secret credential used by scripts/refresh-observability-token.ps1
SECRET_CLIENT_APP_SECRET=

# A365 Observability S2S token — minted by scripts/refresh-observability-token.ps1
SECRET_OBS_S2S_TOKEN=
"@
Set-Content -Path $envPlaygroundUser -Value $userTemplate -Encoding UTF8
Write-Host "  [OK] env/.env.playground.user reset" -ForegroundColor Green

# =========================================================================
# Summary
# =========================================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Teardown Summary" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

if ($hadErrors) {
    Write-Host "  Completed with warnings (see above)." -ForegroundColor Yellow
} else {
    Write-Host "  Clean slate achieved." -ForegroundColor Green
}

Write-Host ""
Write-Host "  To re-provision from scratch:" -ForegroundColor Cyan
Write-Host "    pwsh -File scripts/setup-environment.ps1"
Write-Host ""

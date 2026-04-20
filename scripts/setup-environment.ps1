# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

<#
.SYNOPSIS
    Complete environment setup for the A365 Governed Pro-Code Agent Starter.
    Provisions all Azure resources, Entra app registrations, and A365 blueprint.

.DESCRIPTION
    This script automates the full setup:
      1. Azure OpenAI resource + gpt-4o-mini deployment
      2. Entra client app registration with delegated permissions
      3. A365 CLI config init + setup all
      4. Observability S2S role assignment
      5. .env file generation

    Run from the project root (the repository folder).
    Requires: az CLI, .NET 8+, Python 3.11+, PowerShell 7+

.PARAMETER AgentName
    Alphanumeric agent name (no special chars). Default: procodeagent

.PARAMETER Location
    Azure region. Default: eastus

.PARAMETER SkuTier
    App Service Plan SKU. Default: F1 (Free)

.PARAMETER OpenAIModel
    Azure OpenAI model to deploy. Default: gpt-4o-mini

.EXAMPLE
    .\scripts\setup-environment.ps1
    .\scripts\setup-environment.ps1 -AgentName "myagent" -Location "westus"
#>

param(
    [string]$AgentName = "procodeagent",
    [string]$Location = "eastus",
    [string]$SkuTier = "F1",
    [string]$OpenAIModel = "gpt-4o-mini",
    [string]$ResourceGroup = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = $PSScriptRoot | Split-Path -Parent

if (-not $ResourceGroup) { $ResourceGroup = "rg-a365-$AgentName" }

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " A365 Governed Pro-Code Agent Starter - Environment Setup" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Agent Name:     $AgentName"
Write-Host "Resource Group: $ResourceGroup"
Write-Host "Location:       $Location"
Write-Host "SKU:            $SkuTier"
Write-Host "Model:          $OpenAIModel"
Write-Host "Project Root:   $ProjectRoot"
Write-Host ""

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

# --- Step 0: Validate prerequisites ---
Write-Stage 0 "Prerequisites" `
    -What "Verify pwsh, az, a365 CLI, and uv are installed and on PATH." `
    -Why "Every later step assumes these are present; failing fast keeps a 60-line trace from collapsing into a confusing 600-line one." `
    -Proves "The local box is ready to drive Azure + Entra + Python provisioning."

$prereqs = @(
    @{ Name = "az CLI";       Cmd = "az --version" },
    @{ Name = "dotnet";       Cmd = "dotnet --version" },
    @{ Name = "python";       Cmd = "python --version" },
    @{ Name = "git";          Cmd = "git --version" }
)

foreach ($p in $prereqs) {
    try {
        $null = Invoke-Expression $p.Cmd 2>$null
        Write-Host "  [OK] $($p.Name)" -ForegroundColor Green
    } catch {
        Write-Error "$($p.Name) not found. Install it first."
        exit 1
    }
}

# Check pwsh (PowerShell 7+)
$pwshPath = Get-Command pwsh -ErrorAction SilentlyContinue
if (-not $pwshPath) {
    Write-Host "  [MISSING] PowerShell 7+ - installing via winget..." -ForegroundColor Yellow
    winget install --id Microsoft.PowerShell --source winget --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    Write-Host "  [OK] PowerShell 7+ installed" -ForegroundColor Green
} else {
    Write-Host "  [OK] PowerShell 7+" -ForegroundColor Green
}

# Check A365 CLI
$a365Path = Get-Command a365 -ErrorAction SilentlyContinue
if (-not $a365Path) {
    Write-Host "  [MISSING] A365 CLI - installing..." -ForegroundColor Yellow
    dotnet tool install --global Microsoft.Agents.A365.DevTools.Cli --prerelease 2>&1 | Out-Null
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    Write-Host "  [OK] A365 CLI installed" -ForegroundColor Green
} else {
    Write-Host "  [OK] A365 CLI" -ForegroundColor Green
}

# --- Step 1: Verify Azure login ---
Write-Host ""
Write-Stage 1 "Azure login" `
    -What "Resolve current az subscription + tenant context." `
    -Why "Every cloud and Entra call below runs as this identity. Wrong context = wrong tenant = wrong evidence." `
    -Proves "All later artifacts (RG, blueprint, agent identity) belong to the same tenant + subscription."

$account = az account show --output json 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Host "Not logged in. Running az login..." -ForegroundColor Yellow
    az login
    $account = az account show --output json | ConvertFrom-Json
}

$SubscriptionId = $account.id
$TenantId = $account.tenantId
$UserEmail = $account.user.name

Write-Host "  Subscription: $($account.name) ($SubscriptionId)" -ForegroundColor Green
Write-Host "  Tenant:       $TenantId" -ForegroundColor Green
Write-Host "  User:         $UserEmail" -ForegroundColor Green

# --- Step 1b: Resolve default verified tenant domain for agent UPN ---
# G10 fix: agentUserPrincipalName must use a tenant-owned verified domain so the
# agent gets a real, addressable mailbox. Falls back to tenant GUID-based lookup.
$domainsJson = az rest --method GET --url "https://graph.microsoft.com/v1.0/domains" --output json 2>$null | ConvertFrom-Json
$defaultDomain = ($domainsJson.value | Where-Object { $_.isDefault -and $_.isVerified } | Select-Object -First 1).id
if (-not $defaultDomain) {
    $defaultDomain = ($domainsJson.value | Where-Object { $_.isVerified } | Select-Object -First 1).id
}
if (-not $defaultDomain) {
    Write-Error "Could not resolve a verified tenant domain. Ensure az CLI has Directory.Read.All."
    exit 1
}
Write-Host "  Domain:       $defaultDomain" -ForegroundColor Green

# --- Step 2: Provision Azure OpenAI resource + model deployment ---
Write-Host ""
Write-Stage 2 "Azure OpenAI provisioning" `
    -What "Create a resource group + Azure OpenAI account + model deployment for the agent's LLM backend." `
    -Why "The agent needs an LLM endpoint. Bringing it up via Azure OpenAI keeps the data plane inside the same Azure subscription as the rest of the demo." `
    -Proves "The pro-code agent has an enterprise-grade model endpoint it can call from agent.py."

$OpenAIResourceName = "$AgentName-openai"

# Create resource group if it doesn't exist
$rgExists = az group exists --name $ResourceGroup 2>$null
if ($rgExists -ne "true") {
    Write-Host "  Creating resource group $ResourceGroup..."
    az group create --name $ResourceGroup --location $Location --output none
}

# Check if Azure OpenAI resource exists
$aoaiExists = az cognitiveservices account show --name $OpenAIResourceName --resource-group $ResourceGroup --output json 2>$null
if (-not $aoaiExists) {
    Write-Host "  Creating Azure OpenAI resource: $OpenAIResourceName..."
    az cognitiveservices account create `
        --name $OpenAIResourceName `
        --resource-group $ResourceGroup `
        --location $Location `
        --kind OpenAI `
        --sku S0 `
        --output none 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [WARN] Azure OpenAI creation failed. You may need to request access or try a different region." -ForegroundColor Yellow
        Write-Host "  Falling back to OpenAI API key mode. Set OPENAI_API_KEY in .env manually." -ForegroundColor Yellow
        $UseAzureOpenAI = $false
    } else {
        Write-Host "  [OK] Azure OpenAI resource created" -ForegroundColor Green
        $UseAzureOpenAI = $true
    }
} else {
    Write-Host "  [OK] Azure OpenAI resource already exists" -ForegroundColor Green
    $UseAzureOpenAI = $true
}

$AzureOpenAIEndpoint = ""
$AzureOpenAIKey = ""
$DeploymentName = ""

if ($UseAzureOpenAI) {
    # Get endpoint and key
    $aoaiInfo = az cognitiveservices account show --name $OpenAIResourceName --resource-group $ResourceGroup --output json | ConvertFrom-Json
    $AzureOpenAIEndpoint = $aoaiInfo.properties.endpoint

    $keys = az cognitiveservices account keys list --name $OpenAIResourceName --resource-group $ResourceGroup --output json | ConvertFrom-Json
    $AzureOpenAIKey = $keys.key1

    Write-Host "  Endpoint: $AzureOpenAIEndpoint"

    # Deploy model
    $DeploymentName = $OpenAIModel
    $deployExists = az cognitiveservices account deployment show --name $OpenAIResourceName --resource-group $ResourceGroup --deployment-name $DeploymentName --output json 2>$null
    if (-not $deployExists) {
        Write-Host "  Deploying model: $OpenAIModel as '$DeploymentName'..."
        az cognitiveservices account deployment create `
            --name $OpenAIResourceName `
            --resource-group $ResourceGroup `
            --deployment-name $DeploymentName `
            --model-name $OpenAIModel `
            --model-version "2024-07-18" `
            --model-format OpenAI `
            --sku-capacity 10 `
            --sku-name "GlobalStandard" `
            --output none 2>&1

        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [WARN] Model deployment failed. Trying Standard SKU..." -ForegroundColor Yellow
            az cognitiveservices account deployment create `
                --name $OpenAIResourceName `
                --resource-group $ResourceGroup `
                --deployment-name $DeploymentName `
                --model-name $OpenAIModel `
                --model-version "2024-07-18" `
                --model-format OpenAI `
                --sku-capacity 10 `
                --sku-name "Standard" `
                --output none 2>&1
        }
        Write-Host "  [OK] Model deployed: $DeploymentName" -ForegroundColor Green
    } else {
        Write-Host "  [OK] Model deployment already exists: $DeploymentName" -ForegroundColor Green
    }
}

# --- Step 3: Register Entra client app ---
Write-Host ""
Write-Stage 3 "Entra client app" `
    -What "Register a delegated/public client app with Graph permissions needed by the A365 CLI and bearer-token flow." `
    -Why "a365 CLI runs as a delegated user with these scopes; Playground bearer tokens are minted against this app." `
    -Proves "There is a single named Entra principal that the operator can use end-to-end without ad-hoc consent prompts later."

$ClientAppName = "$AgentName-cli-app"
$existingApp = az ad app list --display-name $ClientAppName --output json 2>$null | ConvertFrom-Json

if ($existingApp -and $existingApp.Count -gt 0) {
    $ClientAppId = $existingApp[0].appId
    Write-Host "  [OK] Client app already exists: $ClientAppId" -ForegroundColor Green
} else {
    Write-Host "  Creating client app: $ClientAppName..."
    $appResult = az ad app create --display-name $ClientAppName --sign-in-audience "AzureADMyOrg" --public-client-redirect-uris "http://localhost:8400/" "http://localhost" --output json | ConvertFrom-Json
    $ClientAppId = $appResult.appId
    Write-Host "  [OK] Created: $ClientAppId" -ForegroundColor Green
}

# Configure redirect URIs + public client
Write-Host "  Configuring redirect URIs..."
az ad app update --id $ClientAppId `
    --public-client-redirect-uris "http://localhost:8400/" "http://localhost" "ms-appx-web://Microsoft.AAD.BrokerPlugin/$ClientAppId" `
    --set isFallbackPublicClient=true `
    --output none 2>&1

# Add delegated permissions
Write-Host "  Adding delegated permissions..."
$GraphId = "00000003-0000-0000-c000-000000000000"
$graphSp = az ad sp show --id $GraphId --output json | ConvertFrom-Json

$requiredPerms = @(
    "AgentIdentityBlueprint.ReadWrite.All",
    "AgentIdentityBlueprint.UpdateAuthProperties.All",
    "AgentIdentityBlueprint.AddRemoveCreds.All",
    "Application.ReadWrite.All",
    "DelegatedPermissionGrant.ReadWrite.All",
    "Directory.Read.All",
    "User.ReadWrite.All"
)

$permArgs = @()
foreach ($perm in $requiredPerms) {
    $found = $graphSp.oauth2PermissionScopes | Where-Object { $_.value -eq $perm }
    if ($found) {
        $permArgs += "$($found.id)=Scope"
    } else {
        Write-Host "  [WARN] Permission not found: $perm" -ForegroundColor Yellow
    }
}

if ($permArgs.Count -gt 0) {
    az ad app permission add --id $ClientAppId --api $GraphId --api-permissions @permArgs --output none 2>&1
    Write-Host "  Granting admin consent..."
    az ad app permission admin-consent --id $ClientAppId --output none 2>&1
    Write-Host "  [OK] Permissions configured + consent granted" -ForegroundColor Green
}

# --- Step 4: Python virtual environment ---
Write-Host ""
Write-Stage 4 "Python environment" `
    -What "Create .venv via uv and install this repo + dev extras (microsoft_agents_a365_*, openai-agents, etc.)." `
    -Why "The agent code, the OTel exporter, and the test scripts all run from this venv." `
    -Proves "All A365 SDK packages and tooling are importable; the rest of the demo can run."

Set-Location $ProjectRoot

if (-not (Test-Path ".venv")) {
    Write-Host "  Creating virtual environment..."
    uv venv 2>&1 | Out-Null
}

Write-Host "  Installing dependencies..."
& ".venv\Scripts\Activate.ps1"
uv pip install -e ".[dev]" 2>&1 | Out-Null
Write-Host "  [OK] Python environment ready" -ForegroundColor Green

# --- Step 5: Generate playground env files ---
Write-Host ""
Write-Stage 5 "Playground env files" `
    -What "Write env/.env.playground (CLIENT_APP_ID, exporter flags) and env/.env.playground.user (Azure OpenAI key, secret placeholders)." `
    -Why "Playground deploy task reads these files; missing values = silent fallback to broken configurations." `
    -Proves "Pressing F5 launches the agent with all required configuration already in place."

$envPlayground = Join-Path $ProjectRoot "env/.env.playground"
$envPlaygroundUser = Join-Path $ProjectRoot "env/.env.playground.user"

# Update CLIENT_APP_ID in .env.playground
$playgroundContent = Get-Content $envPlayground -Raw
# Replace any CLIENT_APP_ID=<value-or-empty> up to end of line (strips trailing comments/whitespace)
if ($playgroundContent -match '(?m)^CLIENT_APP_ID=.*$') {
    $playgroundContent = $playgroundContent -replace '(?m)^CLIENT_APP_ID=.*$', "CLIENT_APP_ID=$ClientAppId"
    Set-Content -Path $envPlayground -Value $playgroundContent.TrimEnd() -Encoding UTF8
    Write-Host "  [OK] CLIENT_APP_ID set in env/.env.playground" -ForegroundColor Green
} else {
    Write-Host "  [WARN] CLIENT_APP_ID line not found in env/.env.playground" -ForegroundColor Yellow
}

# Populate .env.playground.user with Azure OpenAI credentials
if ($UseAzureOpenAI) {
    $userContent = @"
# LLM Configuration (choose one option)

# Option 1: Azure OpenAI (preferred for enterprise)
SECRET_AZURE_OPENAI_API_KEY=$AzureOpenAIKey
AZURE_OPENAI_ENDPOINT=$AzureOpenAIEndpoint
AZURE_OPENAI_DEPLOYMENT_NAME=$DeploymentName

# Option 2: OpenAI (if Azure OpenAI not configured)
# SECRET_OPENAI_API_KEY=
# OPENAI_MODEL=gpt-4o

SECRET_BEARER_TOKEN=

# Client app federated/secret credential used by scripts/refresh-observability-token.ps1
SECRET_CLIENT_APP_SECRET=

# A365 Observability S2S token — minted by scripts/refresh-observability-token.ps1
SECRET_OBS_S2S_TOKEN=
"@
} else {
    $userContent = @"
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
}
Set-Content -Path $envPlaygroundUser -Value $userContent -Encoding UTF8
Write-Host "  [OK] env/.env.playground.user populated" -ForegroundColor Green

# --- Step 6: Generate a365.config.json + run a365 setup ---
Write-Host ""
Write-Stage 6 "A365 blueprint" `
    -What "Write a365.config.json and run 'a365 setup all' to create the blueprint (agentic Entra app + tooling manifest)." `
    -Why "The blueprint is the single point of governance every agent instance inherits from. Without it, no per-instance scope inheritance works." `
    -Proves "agentBlueprintId exists and is now the only thing an admin needs to govern the entire fleet."

$a365Config = @{
    tenantId                  = $TenantId
    subscriptionId            = $SubscriptionId
    resourceGroup             = $ResourceGroup
    location                  = $Location
    environment               = "prod"
    needDeployment            = $true
    graphBaseUrl              = "https://graph.microsoft.com"
    clientAppId               = $ClientAppId
    appServicePlanName        = "$ResourceGroup-plan"
    appServicePlanSku         = $SkuTier
    webAppName                = "$AgentName-webapp"
    agentIdentityDisplayName  = "$AgentName Identity"
    agentBlueprintDisplayName = "$AgentName Blueprint"
    agentUserPrincipalName    = "$AgentName@$defaultDomain"
    agentUserDisplayName      = "$AgentName Agent User"
    managerEmail              = $UserEmail
    agentUserUsageLocation    = "US"
    deploymentProjectPath     = $ProjectRoot
    agentDescription          = "$AgentName - Agent 365 Agent"
}
$a365Config | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $ProjectRoot "a365.config.json") -Encoding UTF8
Write-Host "  [OK] a365.config.json generated" -ForegroundColor Green

Write-Host "  Running a365 setup all --skip-infrastructure ..."
Write-Host "  (This creates the Entra blueprint and configures permissions)" -ForegroundColor Cyan
Write-Host ""

Set-Location $ProjectRoot
a365 setup all --skip-infrastructure --skip-requirements 2>&1
$setupExitCode = $LASTEXITCODE

if ($setupExitCode -eq 0) {
    Write-Host "  [OK] A365 setup completed" -ForegroundColor Green
} else {
    Write-Host "  [WARN] A365 setup exited with code $setupExitCode" -ForegroundColor Yellow
    Write-Host "  You may need to run manually: a365 setup all --skip-infrastructure" -ForegroundColor Yellow
}

# --- Step 7: Create primary agent identity (under the blueprint just created) ---
Write-Host ""
Write-Stage 7 "Primary agent identity" `
    -What "Run 'a365 create-instance identity' to create the first agentUser bound to the blueprint." `
    -Why "setup all creates the blueprint but no instance. Without this step, the blueprint has zero agents and the demo cannot send a turn." `
    -Proves "agentUser <name>@<tenant> exists with UPN, mailbox, Teams presence, and inherits all blueprint scopes."

# `a365 setup all` creates the blueprint but does NOT create an agent identity.
# Without this step the blueprint has no instances and the agent has no UPN/mailbox.
Set-Location $ProjectRoot
a365 create-instance identity -c a365.config.json 2>&1
$instanceExit = $LASTEXITCODE
if ($instanceExit -eq 0) {
    Write-Host "  [OK] Primary agent identity created" -ForegroundColor Green
} else {
    Write-Host "  [WARN] create-instance identity exited with code $instanceExit" -ForegroundColor Yellow
    Write-Host "  Run manually: a365 create-instance identity -c a365.config.json" -ForegroundColor Yellow
}

# --- Step 8: Assign Agent365.Observability.OtelWrite role to blueprint SP ---
Write-Host ""
Write-Stage 8 "Blueprint OtelWrite role" `
    -What "Assign Agent365.Observability.OtelWrite (8f71190c-...) on Agent365Observability (9b975845-...) to the blueprint SP." `
    -Why "This role is the S2S admission ticket to the A365 telemetry backend. Centralizing it on the blueprint means revocation is atomic across all instances." `
    -Proves "Every instance under this blueprint can mint observability tokens via the blueprint's federated credential."

$obsRoleScript = Join-Path $ProjectRoot "scripts/assign-observability-role.ps1"
if (Test-Path $obsRoleScript) {
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $obsRoleScript
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] OtelWrite role assigned to blueprint SP" -ForegroundColor Green
    } else {
        Write-Host "  [WARN] assign-observability-role.ps1 exited with code $LASTEXITCODE" -ForegroundColor Yellow
    }
} else {
    Write-Host "  [SKIP] scripts/assign-observability-role.ps1 not found" -ForegroundColor Gray
}

# --- Step 9: Mint client-app secret + grant OtelWrite to client app SP ---
# This is the local-dev S2S path used by Playground. The blueprint SP is an agentic app
# and rejects client_credentials (AADSTS82001), so we grant the same role to the client
# app SP and use that to mint observability tokens.
Write-Host ""
Write-Stage 9 "Local-dev S2S bootstrap" `
    -What "Mint a client-secret on the client app, persist it as SECRET_CLIENT_APP_SECRET, then grant OtelWrite to the client app SP." `
    -Why "Blueprint SPs are agentic apps and reject pure client_credentials (AADSTS82001). Granting the same role to the client app SP gives Playground a working S2S path until real agentic auth is enabled." `
    -Proves "refresh-observability-token.ps1 can mint observability tokens locally without a Teams turn."

# Mint a client secret on the client app (idempotent: any existing secret keeps working)
$secretJson = az ad app credential reset --id $ClientAppId --display-name "observability-s2s-$(Get-Date -Format 'yyyyMMdd')" --append --years 1 --output json 2>$null | ConvertFrom-Json
if ($secretJson -and $secretJson.password) {
    $clientSecret = $secretJson.password
    Write-Host "  [OK] Client app secret minted" -ForegroundColor Green

    # Persist to .env.playground.user
    $envUserPath = Join-Path $ProjectRoot "env/.env.playground.user"
    $userText = Get-Content $envUserPath -Raw
    if ($userText -match '(?m)^SECRET_CLIENT_APP_SECRET=.*$') {
        $userText = $userText -replace '(?m)^SECRET_CLIENT_APP_SECRET=.*$', "SECRET_CLIENT_APP_SECRET=$clientSecret"
    } else {
        $userText += "`nSECRET_CLIENT_APP_SECRET=$clientSecret"
    }
    Set-Content -Path $envUserPath -Value $userText.TrimEnd() -Encoding UTF8
    Write-Host "  [OK] SECRET_CLIENT_APP_SECRET written to env/.env.playground.user" -ForegroundColor Green
} else {
    Write-Host "  [WARN] Could not mint client app secret" -ForegroundColor Yellow
}

# Grant Agent365.Observability.OtelWrite to the client app SP (workaround for AADSTS82001)
$ObsApiAppId = "9b975845-388f-4429-889e-eab1ef63949c"  # Agent365Observability
$OtelWriteRoleId = "8f71190c-00c8-461d-a63b-f74abde9ba52"
$clientSpFilter = [uri]::EscapeDataString("appId eq '$ClientAppId'")
$clientSp = (az rest --method GET --uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=$clientSpFilter" --output json 2>$null | ConvertFrom-Json).value | Select-Object -First 1
$obsSpFilter = [uri]::EscapeDataString("appId eq '$ObsApiAppId'")
$obsSp = (az rest --method GET --uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=$obsSpFilter" --output json 2>$null | ConvertFrom-Json).value | Select-Object -First 1

if ($clientSp -and $obsSp) {
    $existing = (az rest --method GET --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$($clientSp.id)/appRoleAssignments" --output json 2>$null | ConvertFrom-Json).value |
        Where-Object { $_.resourceId -eq $obsSp.id -and $_.appRoleId -eq $OtelWriteRoleId }
    if ($existing) {
        Write-Host "  [OK] OtelWrite role already assigned to client app SP" -ForegroundColor Green
    } else {
        $body = @{ principalId = $clientSp.id; resourceId = $obsSp.id; appRoleId = $OtelWriteRoleId } | ConvertTo-Json -Compress
        $tmpBody = New-TemporaryFile
        Set-Content -Path $tmpBody -Value $body -Encoding UTF8
        az rest --method POST --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$($clientSp.id)/appRoleAssignments" --headers "Content-Type=application/json" --body "@$tmpBody" --output none 2>&1 | Out-Null
        Remove-Item $tmpBody -Force -ErrorAction SilentlyContinue
        Write-Host "  [OK] OtelWrite role granted to client app SP" -ForegroundColor Green
    }
} else {
    Write-Host "  [WARN] Could not resolve client app SP or Observability API SP" -ForegroundColor Yellow
}

# --- Step 10: Mint initial OBS_S2S_TOKEN ---
Write-Host ""
Write-Stage 10 "Initial OBS_S2S_TOKEN" `
    -What "Run scripts/refresh-observability-token.ps1 to mint and persist SECRET_OBS_S2S_TOKEN, then flip ENABLE_A365_OBSERVABILITY_EXPORTER=true." `
    -Why "Without a token in hand, the exporter falls back to console mode silently and the F5 demo proves nothing." `
    -Proves "On next F5, the exporter activates and POSTs spans to https://agent365.svc.cloud.microsoft (gated 403 expected on non-Frontier tenants)."

$obsTokenScript = Join-Path $ProjectRoot "scripts/refresh-observability-token.ps1"
if (Test-Path $obsTokenScript) {
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $obsTokenScript
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] SECRET_OBS_S2S_TOKEN minted" -ForegroundColor Green

        # Flip ENABLE_A365_OBSERVABILITY_EXPORTER on now that the token is real
        $envPath = Join-Path $ProjectRoot "env/.env.playground"
        $envText = Get-Content $envPath -Raw
        if ($envText -match '(?m)^ENABLE_A365_OBSERVABILITY_EXPORTER=.*$') {
            $envText = $envText -replace '(?m)^ENABLE_A365_OBSERVABILITY_EXPORTER=.*$', 'ENABLE_A365_OBSERVABILITY_EXPORTER=true'
        } else {
            $envText += "`nENABLE_A365_OBSERVABILITY_EXPORTER=true"
        }
        Set-Content -Path $envPath -Value $envText.TrimEnd() -Encoding UTF8
        Write-Host "  [OK] ENABLE_A365_OBSERVABILITY_EXPORTER=true" -ForegroundColor Green
    } else {
        Write-Host "  [WARN] refresh-observability-token.ps1 exited with code $LASTEXITCODE" -ForegroundColor Yellow
    }
} else {
    Write-Host "  [SKIP] scripts/refresh-observability-token.ps1 not found" -ForegroundColor Gray
}

# --- Step 11: Refresh bearer token ---
Write-Host ""
Write-Stage 11 "Bearer token (delegated)" `
    -What "Device-code login as the operator and mint a 4-min delegated bearer token for Work IQ Tools (Mail/Calendar MCP)." `
    -Why "Playground sends this token in every /api/messages request; the agent uses it to call Mail/Calendar MCP servers as the operator." `
    -Proves "F5 will not 401 on the first message; MCP tools work end-to-end."

$tokenScript = Join-Path $ProjectRoot ".vscode/scripts/refresh-bearer-token.ps1"
if (Test-Path $tokenScript) {
    Write-Host "  Running token refresh script..."
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $tokenScript
    $tokenExitCode = $LASTEXITCODE
    if ($tokenExitCode -eq 0) {
        Write-Host "  [OK] Bearer token refreshed" -ForegroundColor Green
    } else {
        Write-Host "  [WARN] Token refresh exited with code $tokenExitCode" -ForegroundColor Yellow
        Write-Host "  Run manually: pwsh -File .vscode/scripts/refresh-bearer-token.ps1" -ForegroundColor Yellow
    }
} else {
    Write-Host "  [SKIP] Token refresh script not found" -ForegroundColor Gray
}

# --- Summary ---
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Setup Summary" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Resource Group:    $ResourceGroup"
Write-Host "  Azure OpenAI:      $(if ($UseAzureOpenAI) { "$OpenAIResourceName ($AzureOpenAIEndpoint)" } else { 'Not provisioned' })"
Write-Host "  Model Deployment:  $(if ($UseAzureOpenAI) { $DeploymentName } else { 'N/A' })"
Write-Host "  Client App:        $ClientAppName ($ClientAppId)"
Write-Host "  Python venv:       .venv (activated)"
Write-Host "  Env files:         Populated"
Write-Host ""
Write-Host "  Ready to test:" -ForegroundColor Green
Write-Host "    Press F5 to debug in Microsoft 365 Agents Playground"
Write-Host ""
Write-Host "  NOTE: All auth uses device code flow (no WAM)." -ForegroundColor Yellow
Write-Host ""

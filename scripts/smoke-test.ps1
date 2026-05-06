# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

<#
.SYNOPSIS
    Sends a synthetic Bot Framework activity to the locally running agent host.

.DESCRIPTION
    Acts as the bridge between tenant onboarding (setup-environment.ps1) and code
    correctness (pytest). After F5 starts the host on localhost:3978, this script
    POSTs a 'message' activity and asserts the response is 2xx. Exit code 0 on
    success, 1 on failure. Designed to be invoked from CI, from Pester
    (smoke-test.Tests.ps1), or by hand.

.PARAMETER HostUrl
    Base URL of the running agent host. Default: http://localhost:3978

.PARAMETER TenantId
    Tenant id to embed in the activity. Default: the playground tenant.

.PARAMETER AgenticAppId
    Blueprint / agent app id to embed in recipient.agenticAppId.

.PARAMETER Message
    Text to send. Default: 'hello'

.PARAMETER BearerToken
    Authorization bearer token. Default: 'test-token' (Playground accepts).

.EXAMPLE
    .\scripts\smoke-test.ps1
    .\scripts\smoke-test.ps1 -Message "what time is it?" -HostUrl "http://localhost:3978"
#>

[CmdletBinding()]
param(
    [string]$HostUrl = "http://localhost:3978",
    [string]$TenantId = "253bc031-a17c-4b57-b83c-1ee1d86b1331",
    [string]$AgenticAppId = "19bc459c-7807-4a41-a467-4adfb9f9704b",
    [string]$Message = "hello",
    [string]$BearerToken = "test-token",
    [int]$TimeoutSec = 20
)

$ErrorActionPreference = "Stop"

function New-SmokeTestActivity {
    param(
        [Parameter(Mandatory)] [string]$TenantId,
        [Parameter(Mandatory)] [string]$AgenticAppId,
        [Parameter(Mandatory)] [string]$Message
    )

    return @{
        type           = "message"
        id             = "smoke-$(Get-Random)"
        timestamp      = (Get-Date).ToUniversalTime().ToString("o")
        localTimestamp = (Get-Date).ToString("o")
        channelId      = "msteams"
        serviceUrl     = "http://localhost:56150"
        from           = @{
            id          = "29:1test-user"
            name        = "Test User"
            aadObjectId = "cfb40a8b-29bf-4b93-a129-89ab5a84d926"
        }
        conversation   = @{
            id               = "smoke-conv-1"
            conversationType = "personal"
            tenantId         = $TenantId
        }
        recipient      = @{
            id           = "28:bot-1"
            name         = "procodeagent"
            tenantId     = $TenantId
            agenticAppId = $AgenticAppId
        }
        text           = $Message
        textFormat     = "plain"
        locale         = "en-US"
        channelData    = @{ tenant = @{ id = $TenantId } }
    }
}

$headers = @{
    "Authorization" = "Bearer $BearerToken"
    "Content-Type"  = "application/json"
}

$activity = New-SmokeTestActivity -TenantId $TenantId -AgenticAppId $AgenticAppId -Message $Message
$body = $activity | ConvertTo-Json -Depth 10

try {
    $resp = Invoke-WebRequest `
        -Uri "$HostUrl/api/messages" `
        -Method POST `
        -Headers $headers `
        -Body $body `
        -TimeoutSec $TimeoutSec
    Write-Host "STATUS: $($resp.StatusCode)" -ForegroundColor Green
    if ($resp.Content) { Write-Host $resp.Content }
    if ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 300) {
        exit 0
    }
    Write-Host "Non-2xx response" -ForegroundColor Red
    exit 1
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    try { Write-Host ($_.ErrorDetails.Message) } catch {}
    exit 1
}

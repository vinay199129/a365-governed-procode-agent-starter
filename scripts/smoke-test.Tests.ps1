# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

<#
.SYNOPSIS
    Pester 5 tests for scripts/smoke-test.ps1.

.DESCRIPTION
    Verifies activity construction (no live HTTP) by dot-sourcing the helper
    function and asserting the payload shape that the agent host expects.
    Run with: Invoke-Pester scripts/smoke-test.Tests.ps1
#>

BeforeAll {
    $script:SmokeTestPath = Join-Path $PSScriptRoot "smoke-test.ps1"

    # Dot-source the helper function without executing the param block at top
    # by extracting just the function definition.
    $content = Get-Content $script:SmokeTestPath -Raw
    $funcMatch = [regex]::Match(
        $content,
        '(?s)function New-SmokeTestActivity\s*\{.*?^\}',
        [System.Text.RegularExpressions.RegexOptions]::Multiline
    )
    if (-not $funcMatch.Success) {
        throw "Could not extract New-SmokeTestActivity from smoke-test.ps1"
    }
    Invoke-Expression $funcMatch.Value
}

Describe "New-SmokeTestActivity" {
    BeforeAll {
        $script:activity = New-SmokeTestActivity `
            -TenantId "tenant-xyz" `
            -AgenticAppId "blueprint-abc" `
            -Message "hello world"
    }

    It "returns a message activity" {
        $script:activity.type | Should -Be "message"
    }

    It "sets recipient.tenantId from parameter" {
        $script:activity.recipient.tenantId | Should -Be "tenant-xyz"
    }

    It "sets recipient.agenticAppId from parameter (the blueprint id)" {
        $script:activity.recipient.agenticAppId | Should -Be "blueprint-abc"
    }

    It "echoes the user message text" {
        $script:activity.text | Should -Be "hello world"
    }

    It "embeds tenant id under channelData for Teams routing" {
        $script:activity.channelData.tenant.id | Should -Be "tenant-xyz"
    }

    It "uses personal conversation type" {
        $script:activity.conversation.conversationType | Should -Be "personal"
    }

    It "produces a unique activity id per call" {
        $a = New-SmokeTestActivity -TenantId "t" -AgenticAppId "b" -Message "m"
        $b = New-SmokeTestActivity -TenantId "t" -AgenticAppId "b" -Message "m"
        $a.id | Should -Not -Be $b.id
    }
}

Describe "smoke-test.ps1 contract" {
    It "is parameterized (not hardcoded)" {
        $content = Get-Content $script:SmokeTestPath -Raw
        $content | Should -Match 'param\s*\('
        $content | Should -Match '\$HostUrl'
        $content | Should -Match '\$TenantId'
        $content | Should -Match '\$AgenticAppId'
    }

    It "exits with non-zero on failure (has exit 1)" {
        $content = Get-Content $script:SmokeTestPath -Raw
        $content | Should -Match 'exit\s+1'
    }
}

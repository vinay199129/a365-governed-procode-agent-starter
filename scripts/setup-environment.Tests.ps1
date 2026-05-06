# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

<#
.SYNOPSIS
    Pester 5 tests for scripts/setup-environment.ps1.

.DESCRIPTION
    Verifies the parameter contract and pure-logic surface of the setup script
    without executing any az / dotnet / a365 CLI side effects. The script body
    is heavyweight and stateful; these tests guard the inputs and the
    ResourceGroup-derivation default that downstream automation depends on.

    Run with: Invoke-Pester scripts/setup-environment.Tests.ps1
#>

BeforeAll {
    $script:SetupScriptPath = Join-Path $PSScriptRoot "setup-environment.ps1"
    $script:Content = Get-Content $script:SetupScriptPath -Raw
}

Describe "setup-environment.ps1 parameter contract" {
    It "exposes all documented parameters" {
        foreach ($param in @("AgentName", "Location", "SkuTier", "OpenAIModel", "ResourceGroup")) {
            $script:Content | Should -Match "\[string\]\s*\`$$param"
        }
    }

    It "defaults AgentName to 'procodeagent'" {
        $script:Content | Should -Match '\[string\]\$AgentName\s*=\s*"procodeagent"'
    }

    It "defaults Location to 'eastus'" {
        $script:Content | Should -Match '\[string\]\$Location\s*=\s*"eastus"'
    }

    It "defaults SkuTier to F1 (free)" {
        $script:Content | Should -Match '\[string\]\$SkuTier\s*=\s*"F1"'
    }

    It "defaults OpenAIModel to gpt-4o-mini" {
        $script:Content | Should -Match '\[string\]\$OpenAIModel\s*=\s*"gpt-4o-mini"'
    }
}

Describe "setup-environment.ps1 derivations" {
    It "derives ResourceGroup from AgentName when not supplied" {
        $script:Content | Should -Match '\$ResourceGroup\s*=\s*"rg-a365-\$AgentName"'
    }

    It "fails fast on errors (ErrorActionPreference = Stop)" {
        $script:Content | Should -Match '\$ErrorActionPreference\s*=\s*"Stop"'
    }
}

Describe "setup-environment.ps1 GA-channel pinning" {
    It "does NOT pass --prerelease to dotnet tool install (post-GA)" {
        # Catches accidental revert to the pre-GA prerelease channel.
        $script:Content | Should -Not -Match 'dotnet tool install[^\n]*--prerelease'
    }
}

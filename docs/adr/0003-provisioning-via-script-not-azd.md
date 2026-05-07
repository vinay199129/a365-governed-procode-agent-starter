---
section: Architecture Decisions
---
# ADR 0003 — Provisioning ownership: PowerShell script, not azd / Bicep

- **Status:** Accepted (May 7, 2026)
- **Context:** [Architecture review](../../.copilot-tracking/research/subagents/2026-05-07/) flagged that `setup-environment.ps1` does both Azure resource creation and Entra app registration imperatively, instead of via `azd up` + Bicep.

## Decision

Keep `scripts/setup-environment.ps1` as the single owner of all provisioning: Azure resource group, App Service plan, Azure OpenAI deployment, Entra client app registration, Graph permissions, A365 blueprint creation, `.env` file population. Do not migrate to `azd` or Bicep.

The `-SkipPlaygroundConfig` switch (added in commit `e3a5449`) gates the local-dev `.env` writes so prod-shape CI/CD runs can use the same script without clobbering secrets sourced from a CI secret store.

## Why

- **One command to onboard.** `.\scripts\setup-environment.ps1` does *everything*. The repo's primary KPI is "time from clone to first response." Splitting provisioning across `azd up` + a script makes that worse, not better.
- **Entra app registration in Bicep is awkward.** The `Microsoft.Graph/applications` Bicep type exists but is preview/limited. Most teams who try it end up with a `deploymentScripts` resource that runs `az ad app create` inside Bicep — same imperative call, more indirection.
- **azd's value is deployment, not Entra.** Most azd templates that need an app reg run a `preprovision` hook that invokes `az ad app create`. Same imperative call, different wrapper.
- **Cleanup is symmetric.** `teardown-environment.ps1` mirrors the script. With a split (azd for Azure, script for Entra), teardown becomes "azd down, then the script for Entra cleanup" — easy to forget the second step and orphan an app reg.
- **The audience is right.** Anyone running this sample is provisioning their own tenant. IaC benefits (drift detection, multi-environment promotion, code review) don't apply when there's one developer running one script in one tenant.
- **The script is grep-able and reviewable.** `Write-Stage` headers explain *why* each step exists. That's a teaching artefact. Bicep is not.

## Rejected alternatives

- **Hybrid (azd for Azure, script for Entra):** two onboarding tools instead of one, with the same imperative `az ad app create` either way. Strictly worse for the demo audience.
- **Pure Bicep / `azd up`:** loses the teaching artefact, creates a forced step ("learn azd before you can read what's being provisioned"), and still needs imperative Entra calls.

## Production handoff

A customer who productionises this code will replace `setup-environment.ps1` wholesale with their own internal IaC (likely Terraform via their platform team). Optimising for that handoff *now* loses the demo audience without gaining the production audience.

## Triggers to revisit

- This repo gets adopted as a Microsoft-published template that ships to many environments with multi-region deployments.
- We add features that genuinely need IaC primitives — Bicep modules, parameter files, `azd env list` / `azd env new` workflows.
- The script crosses ~1000 lines and re-running it stops being safely idempotent.

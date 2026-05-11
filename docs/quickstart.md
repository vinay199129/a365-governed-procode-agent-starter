# Quickstart

Get from a fresh tenant to a running, governed agent in **under an hour**.
This page is the condensed runbook; the [setup walkthrough](setup-walkthrough.md)
explains every step in detail.

## Prerequisites

You need:

- **Python 3.11+**
- **PowerShell 7+** (`pwsh`) — required by the A365 CLI
- **Azure CLI**, signed in via `az login`
- **Microsoft Agent 365 CLI** (`a365`)
- **[Microsoft 365 Agents Toolkit](https://aka.ms/teams-toolkit)** VS Code extension
- **Azure OpenAI** (or OpenAI direct) credentials

> **Tenant note.** The setup script provisions Entra objects (blueprint,
> agent identity) plus an Azure OpenAI deployment in your subscription.
> Use a non-production tenant the first time.

> **Identity note.** To exercise the **MCP tool calls** (Mail / Calendar /
> SharePoint / Teams) you must sign in to the bearer-token refresh script as a
> **licensed M365 work/school account** in the same tenant
> (`you@yourtenant.onmicrosoft.com`). Guest accounts, personal MSAs
> (`@gmail.com`, `@outlook.com` / `live.com` IDP), and unlicensed members will
> cause every MCP server to return HTTP 500 — the bot will still reply, but
> from the LLM only. See
> [TROUBLESHOOTING.md → MCP servers all return HTTP 500](../TROUBLESHOOTING.md#mcp-servers-all-return-http-500-mcp_mailtools-mcp_calendartools-etc)
> for details.

## Two onboarding paths

A365 supports two ways to provision the platform side. Pick the one that fits.

### Path A — AI-guided setup (portal)

Visit [aka.ms/agent365enable](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/get-started)
for Microsoft's hosted AI-guided onboarding. It walks an admin through
subscription, region, blueprint, and agent-identity creation, asking two
policy questions up front: which **capability tier** you want
(Register → Observability → Work IQ → AI teammate — see
[learning-guide Section 1.5](learning-guide.md)) and which **auth flow** your agents
will use (OBO / S2S / Both — see [learning-guide Section 2.5](learning-guide.md)).
When it finishes, jump straight to the [Verify](#verify) section below.

### Path B — Scripted setup (three commands)

Use this for CI, audit-trail, or repeat runs on a clean tenant. This is the
path this starter's evidence captures exercise.

```pwsh
# 1. Provision Azure OpenAI + Entra client app + A365 blueprint + agent identity + tokens.
#    Two WAM popups appear inside `a365 setup all`; accept them.
pwsh -NoProfile -File scripts/setup-environment.ps1

# 2. Mint the short-lived bearer token Playground needs on the first turn.
pwsh -NoProfile -File .vscode/scripts/refresh-bearer-token.ps1

# 3. In VS Code: open the Microsoft 365 Agents Toolkit panel,
#    then press F5 → "Debug in Microsoft 365 Agents Playground".
```

## Verify

In the Playground browser tab, send `hello`. You should see:

- A response from the agent
- `Activity received` logs in the integrated terminal with `from_property` fields
- An OpenTelemetry export attempt (HTTP 200 on a Frontier-enrolled tenant;
  HTTP 403 otherwise — see [project scope](project-scope.md) row G9 for why
  AI-teammate-tier ingest is still Frontier-gated at GA)

## Reset

To wipe the tenant and re-provision (the **round-trip reproducibility test**):

```pwsh
pwsh -NoProfile -File scripts/teardown-environment.ps1 -SkipConfirmation
pwsh -NoProfile -File scripts/setup-environment.ps1
```

The most recent reference round-trip with identifiers and per-step outcomes
is in [evidence/round-trip](evidence/round-trip.md).

## What now?

- New to A365? Read the [concept walkthrough](learning-guide.md).
- Want to understand the code? Start with the
  [architecture overview](design.md) and then the
  [request flow trace](code-walkthrough.md).
- Hit a problem? See [troubleshooting](troubleshooting.md).

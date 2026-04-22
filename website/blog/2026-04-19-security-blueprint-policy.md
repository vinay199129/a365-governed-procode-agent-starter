---
slug: security-blueprint-policy
title: The Security Blueprint — one policy, every instance
authors: starter-team
tags: [governance, blueprint, scopes]
date: 2026-04-19
---

An A365 Security Blueprint is the Entra-registered policy set every agent
instance inherits. Here is what is in this starter's blueprint, why those
scopes, and how inheritance is verified.

<!-- truncate -->

## What the blueprint declares

**Identity & registration**

| Field | Value |
| --- | --- |
| Blueprint display name | `<AgentName> Blueprint` |
| Agent Identity display name | `<AgentName> Identity` |
| Agent UPN | `<AgentName>@<verified-tenant-domain>` |
| Usage location | `US` |

**Inherited delegated scopes**

- **Microsoft Graph:** `User.Read.All`, `Mail.Send`, `Mail.ReadWrite`,
  `Chat.Read`, `Chat.ReadWrite`, `Files.Read.All`, `Sites.Read.All`,
  `ChannelMessage.Read.All`, `ChannelMessage.Send`, `Files.ReadWrite.All`
- **Work IQ Tools:** `McpServers.Mail.All`, `McpServersMetadata.Read.All`, `McpServers.Calendar.All`

All scopes use `consentType=AllPrincipals` so users see no consent prompt.

## Key concepts in five bullets

- **One source of truth** — the blueprint SP is the only place scopes are declared.
- **Verified empirically** — see the [inheritance evidence post](./evidence-multi-instance-inheritance.md).
- **Scope changes are blueprint-level** — instances inherit on next provision.
- **Tenant UPN, not `onmicrosoft.com`** — agents look like real users.
- **MCP scopes are first-class** — they gate the tools the agent can call.

## Try it yourself

```pwsh
code docs/blueprint-policy.md
code a365.generated.config.json

# Inspect what landed in Entra.
az ad sp show --id <agentBlueprintId> --query "appRoles,oauth2PermissionScopes"

# Provision a second instance against the same blueprint.
pwsh -NoProfile -File scripts/provision-second-instance.ps1
```

## Go deeper

- Canonical doc: [Governance: Blueprint policy](/docs/blueprint-policy)
- [Multi-instance evidence](/docs/evidence/multi-instance-inheritance)

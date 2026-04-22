---
title: "The Security Blueprint — one policy, every instance"
date: 2026-04-19
categories: [a365, governance]
tags: [blueprint, scopes, entra, policy]
excerpt: >-
  An A365 Security Blueprint is the Entra-registered policy set every agent
  instance inherits. Here is what is in this starter's blueprint, why those
  scopes, and how inheritance is verified.
---

## Why this post matters

Per-instance config drift is how governance fails in production. A365's
answer is the **Security Blueprint**: register the posture *once*, and
every instance you spin up inherits it byte-for-byte.

The full policy set lives in
[`docs/blueprint-policy.md`](../../../docs/blueprint-policy.md). This
post highlights the parts you'll actually be asked about in a security
review.

## What the blueprint declares

**Identity & registration**

| Field | Value |
| --- | --- |
| Blueprint display name | `<AgentName> Blueprint` |
| Agent Identity display name | `<AgentName> Identity` |
| Agent UPN | `<AgentName>@<verified-tenant-domain>` |
| Usage location | `US` |

**Inherited delegated scopes** (every instance gets these — no overrides)

- **Microsoft Graph:** `User.Read.All`, `Mail.Send`, `Mail.ReadWrite`,
  `Chat.Read`, `Chat.ReadWrite`, `Files.Read.All`, `Sites.Read.All`,
  `ChannelMessage.Read.All`, `ChannelMessage.Send`, `Files.ReadWrite.All`
- **Work IQ Tools:** `McpServers.Mail.All`, `McpServersMetadata.Read.All`,
  `McpServers.Calendar.All`

All scopes are granted with `consentType=AllPrincipals` so users don't
see consent prompts on first use.

## Key concepts in five bullets

- **One source of truth** — the blueprint SP is the *only* place scopes
  are declared. Instance SPs are derived, not authored.
- **Verified empirically, not assumed** — see the
  [multi-instance inheritance evidence post]({% post_url 2026-04-20-evidence-multi-instance-inheritance %})
  for the byte-by-byte diff across two provisioned instances.
- **Scope changes are blueprint-level** — to add a Graph permission,
  edit the blueprint and re-register; instances pick it up.
- **Tenant UPN, not `onmicrosoft.com`** — agents look like real users
  in the directory and in Teams.
- **MCP scopes are first-class** — `McpServers.Mail.All` and
  `McpServers.Calendar.All` gate the tools the agent can actually call.

## Try it yourself

```pwsh
# 1. Open the policy doc.
code docs/blueprint-policy.md

# 2. Inspect the generated config to see your blueprint id.
code a365.generated.config.json

# 3. List what landed in Entra (read-only).
az ad sp show --id <agentBlueprintId> --query "appRoles,oauth2PermissionScopes"

# 4. Provision a *second* instance against the same blueprint and
#    confirm it inherits the same scopes.
pwsh -NoProfile -File scripts/provision-second-instance.ps1
```

The third command requires the blueprint id from
`a365.generated.config.json`; the fourth produces the artifacts the
inheritance evidence post analyses.

## Go deeper

- Canonical doc: [`docs/blueprint-policy.md`](../../../docs/blueprint-policy.md)
- Inheritance evidence: [`docs/evidence/multi-instance-inheritance.md`](../../../docs/evidence/multi-instance-inheritance.md)
- A365 governance overview: <https://learn.microsoft.com/en-us/microsoft-agent-365/developer/>

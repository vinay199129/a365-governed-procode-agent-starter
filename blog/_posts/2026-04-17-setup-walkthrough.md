---
title: "Setup walkthrough — what `setup-environment.ps1` actually provisions"
date: 2026-04-17
categories: [a365, setup]
tags: [setup, azure, entra, blueprint, automation]
excerpt: >-
  A single PowerShell script provisions Azure OpenAI, an Entra client app, an
  A365 Security Blueprint, an Agent Identity, and the local env files.
  Here is what it does — step by step — so nothing feels like magic.
---

## Why this post matters

The starter ships **one command** that takes you from an empty tenant to a
running, governed agent:

```pwsh
pwsh -NoProfile -File scripts/setup-environment.ps1
```

That convenience hides a lot of moving parts. If something fails halfway —
or if you're being asked *"what landed in our tenant?"* — you need a
mental map of every step. That map is
[`docs/setup-walkthrough.md`](../../../docs/setup-walkthrough.md); this
post is the short narrated version.

## What the script provisions, in order

| Step | What lands | Where |
| --- | --- | --- |
| 0 | Prereq checks (Azure CLI, A365 CLI, `pwsh`, Python) | local |
| 1 | Verify subscription + verified tenant domain | Azure + Graph (read-only) |
| 2 | Resource group + Azure OpenAI account + `gpt-4o-mini` deployment | Azure |
| 3 | Entra **client app + service principal** with 7 Graph delegated scopes | Entra |
| 4 | A365 **Security Blueprint** registered against the client app | Entra (via `a365` CLI) |
| 5 | A365 **Agent Identity** with tenant UPN (`<AgentName>@<verified-domain>`) | Entra |
| 6 | Role assignments for OTel ingest + observability | Azure RBAC |
| 7 | Bearer token + S2S token minted | local cache |
| 8 | `env/.env.playground` and `env/.env.playground.user` populated | local files |

Two **WAM popups** appear during step 4 (`a365 setup all`). Accept both —
they're how the A365 CLI gets delegated consent for blueprint creation.

## Key concepts in five bullets

- **Idempotent** — re-running `setup-environment.ps1` is safe; existing
  resources are reused, not duplicated.
- **Round-trippable** — `teardown-environment.ps1` removes everything
  step 1 onward so you can prove reproducibility. See the
  [round-trip evidence post]({% post_url 2026-04-21-evidence-roundtrip %}).
- **No hidden state** — every artifact id lands in
  `a365.generated.config.json` so you can audit it later.
- **Verified-domain UPN** — the agent identity uses your tenant's
  verified domain, not `onmicrosoft.com`, so it appears as a real user
  to other tenant members.
- **Two-token model** — the bearer token (4-min TTL, refreshed before
  F5) is separate from the long-lived S2S observability token.

## Try it yourself

```pwsh
# 1. Sign in to your Azure tenant.
az login
az account set --subscription "<your-subscription>"

# 2. Provision everything (~5 min, two WAM popups).
pwsh -NoProfile -File scripts/setup-environment.ps1

# 3. Inspect what landed.
code a365.generated.config.json
code env/.env.playground

# 4. When you want to wipe and re-prove reproducibility:
pwsh -NoProfile -File scripts/teardown-environment.ps1 -SkipConfirmation
pwsh -NoProfile -File scripts/setup-environment.ps1
```

If a step fails, check
[`TROUBLESHOOTING.md`](../../../TROUBLESHOOTING.md) before re-running —
several known failure modes have one-line fixes.

## Go deeper

- Canonical doc: [`docs/setup-walkthrough.md`](../../../docs/setup-walkthrough.md)
- Script index: [`scripts/README.md`](../../../scripts/README.md)
- Troubleshooting: [`TROUBLESHOOTING.md`](../../../TROUBLESHOOTING.md)

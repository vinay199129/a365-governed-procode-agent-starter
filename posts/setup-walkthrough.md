---
slug: setup-walkthrough
title: "Setup walkthrough — what setup-environment.ps1 actually provisions"
authors: starter-team
tags: [setup, azure, entra]
date: 2026-04-17
---

A single PowerShell script provisions Azure OpenAI, an Entra client app, an
A365 Security Blueprint, an Agent Identity, and the local env files. Here
is what it does — step by step — so nothing feels like magic.

<!-- truncate -->

## What the script provisions, in order

| Step | What lands | Where |
| --- | --- | --- |
| 0 | Prereq checks | local |
| 1 | Verify subscription + verified tenant domain | Azure + Graph (read) |
| 2 | Resource group + Azure OpenAI account + `gpt-4o-mini` deployment | Azure |
| 3 | Entra client app + service principal with 7 Graph delegated scopes | Entra |
| 4 | A365 **Security Blueprint** registered against the client app | Entra (`a365` CLI) |
| 5 | A365 **Agent Identity** with tenant UPN | Entra |
| 6 | Role assignments for OTel ingest + observability | Azure RBAC |
| 7 | Bearer token + S2S token minted | local cache |
| 8 | `env/.env.playground` and `env/.env.playground.user` populated | local files |

Two **WAM popups** appear during step 4 (`a365 setup all`). Accept both.

## Key concepts in five bullets

- **Idempotent** — re-running setup is safe.
- **Round-trippable** — teardown + re-provision recovers a clean state.
- **No hidden state** — every artifact id lands in `a365.generated.config.json`.
- **Verified-domain UPN** — the agent identity uses your tenant's verified domain.
- **Two-token model** — bearer (4-min) vs. S2S observability token.

## Try it yourself

```pwsh
az login
az account set --subscription "<your-subscription>"
pwsh -NoProfile -File scripts/setup-environment.ps1
code a365.generated.config.json
```

## Go deeper

- Canonical doc: [Setup walkthrough](docs.html?doc=setup-walkthrough)
- [Troubleshooting](docs.html?doc=troubleshooting)

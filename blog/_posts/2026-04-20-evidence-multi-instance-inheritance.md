---
title: "Evidence — multi-instance blueprint inheritance"
date: 2026-04-20
categories: [a365, evidence]
tags: [blueprint, inheritance, governance, proof]
excerpt: >-
  Claim: every agent instance inherits its blueprint posture byte-for-byte.
  Here is the captured proof — two instances, one blueprint, scope-set diff.
---

## Why this post matters

Governance claims are only as good as the evidence behind them. The
[blueprint policy post]({% post_url 2026-04-19-security-blueprint-policy %})
asserts that **every instance inherits the same scope set, byte-for-byte,
no per-instance overrides**. This post is the receipt.

The captured artefacts (commands, IDs, raw scope arrays, diff output)
live in [`docs/evidence/multi-instance-inheritance.md`](../../../docs/evidence/multi-instance-inheritance.md).

## What was tested

1. Provision instance **A** against the blueprint via the standard
   setup script.
2. Provision instance **B** against the *same* blueprint via
   `scripts/provision-second-instance.ps1`.
3. Read both instance SPs' delegated scope sets via Microsoft Graph.
4. Diff the scope arrays.

Result: **identical sets** — same Graph scopes, same Work IQ MCP scopes,
same `consentType`. No drift, no per-instance override path observed.

## Key concepts in five bullets

- **Inheritance is a *runtime* property** — instances don't carry their
  own copy of the policy; they resolve scopes through the blueprint SP.
- **Reproducible** — anyone with the repo can run the same two scripts
  and produce the same diff.
- **Pre-Frontier safe** — this evidence runs entirely against Entra and
  needs no A365 backend access.
- **Tenant-portable** — re-running in a fresh tenant produces the same
  result with new IDs; only the IDs differ.
- **Foundation for compliance review** — this is the artefact you hand
  to a security reviewer when they ask *"prove the second instance
  can't ask for more."*

## Try it yourself

```pwsh
# 1. Make sure instance A exists (Quickstart already did this).
pwsh -NoProfile -File scripts/setup-environment.ps1

# 2. Provision instance B against the same blueprint.
pwsh -NoProfile -File scripts/provision-second-instance.ps1

# 3. Pull the scope sets from Entra and diff them yourself.
$blueprintId = (Get-Content a365.generated.config.json | ConvertFrom-Json).agentBlueprintId
$instanceAId = (Get-Content a365.generated.config.json | ConvertFrom-Json).agentInstanceId
$instanceBId = (Get-Content a365.generated.config.json | ConvertFrom-Json).agentInstanceBId

az ad sp show --id $instanceAId --query "oauth2PermissionScopes" -o json > a.json
az ad sp show --id $instanceBId --query "oauth2PermissionScopes" -o json > b.json
git diff --no-index a.json b.json   # expect: no diff
```

For the captured evidence (with real IDs from a prior run) open the
canonical doc.

## Go deeper

- Canonical evidence: [`docs/evidence/multi-instance-inheritance.md`](../../../docs/evidence/multi-instance-inheritance.md)
- Blueprint policy: [`docs/blueprint-policy.md`](../../../docs/blueprint-policy.md)
- Provisioning script: [`scripts/provision-second-instance.ps1`](../../../scripts/provision-second-instance.ps1)

---
slug: evidence-multi-instance-inheritance
title: Evidence — multi-instance blueprint inheritance
authors: starter-team
tags: [evidence, governance, inheritance]
date: 2026-04-20
---

Claim: every agent instance inherits its blueprint posture byte-for-byte.
Here is the captured proof — two instances, one blueprint, scope-set diff.

<!-- truncate -->

## What was tested

1. Provision instance **A** via the standard setup script.
2. Provision instance **B** against the *same* blueprint via
   `scripts/provision-second-instance.ps1`.
3. Read both instance SPs' delegated scope sets via Microsoft Graph.
4. Diff the scope arrays.

**Result: identical sets** — same Graph scopes, same Work IQ MCP scopes,
same `consentType`. No drift, no per-instance override path observed.

## Key concepts in five bullets

- **Inheritance is a runtime property** — instances resolve scopes through the blueprint SP.
- **Reproducible** — anyone with the repo can reproduce the diff.
- **Pre-Frontier safe** — runs entirely against Entra; no A365 backend needed.
- **Tenant-portable** — only the IDs differ across tenants.
- **Foundation for compliance review** — hand this to your security reviewer.

## Try it yourself

```pwsh
pwsh -NoProfile -File scripts/setup-environment.ps1
pwsh -NoProfile -File scripts/provision-second-instance.ps1

$cfg = Get-Content a365.generated.config.json | ConvertFrom-Json
az ad sp show --id $cfg.agentInstanceId  --query "oauth2PermissionScopes" -o json > a.json
az ad sp show --id $cfg.agentInstanceBId --query "oauth2PermissionScopes" -o json > b.json
git diff --no-index a.json b.json   # expect: no diff
```

## Go deeper

- Canonical evidence: [Multi-instance inheritance](docs.html?doc=evidence/multi-instance-inheritance)
- [Blueprint policy](docs.html?doc=blueprint-policy)

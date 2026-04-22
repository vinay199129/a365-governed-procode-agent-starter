---
slug: evidence-roundtrip
title: Evidence — teardown → setup round-trip reproducibility
authors: starter-team
tags: [evidence, reproducibility]
date: 2026-04-21
---

Claim: the starter is fully reproducible — wipe everything, re-provision,
and you land on an identical working state. Here is the captured
round-trip with per-step outcomes.

<!-- truncate -->

## What was tested

1. **Teardown** — remove the resource group, Entra client app, blueprint, agent identity, role assignments, env files.
2. **Re-provision** — run `setup-environment.ps1` from scratch.
3. **Smoke test** — start the host, send `hello`, confirm a turn completes and OTel emits.

Each step's outcome (✅ / ⚠️ / ❌ with notes) is recorded in the canonical evidence doc.

## Key concepts in five bullets

- **Idempotent setup** — safe to re-run after a partial teardown.
- **Best-effort teardown** — keeps going on per-step failures and reports a summary.
- **Confirmation guardrail** — `-SkipConfirmation` required for unattended runs.
- **Smoke test in the loop** — exits non-zero on a failed turn so CI can gate on it.
- **Generated config tells the story** — only IDs change between runs, not shape.

## Try it yourself

```pwsh
pwsh -NoProfile -File scripts/teardown-environment.ps1 -SkipConfirmation
pwsh -NoProfile -File scripts/setup-environment.ps1
pwsh -NoProfile -File .vscode/scripts/refresh-bearer-token.ps1
pwsh -NoProfile -File scripts/smoke-test.ps1
```

## Where to go from here

- **Build on the starter** — swap `agent.py` for your own implementation of `agent_interface.py`.
- **Add a tool** — register a new MCP server; no host changes needed.
- **Re-run the round-trip** — anytime you change setup or teardown, prove it still reproduces.

## Go deeper

- Canonical evidence: [Round-trip](/docs/evidence/round-trip)
- [Setup walkthrough](/docs/setup-walkthrough)

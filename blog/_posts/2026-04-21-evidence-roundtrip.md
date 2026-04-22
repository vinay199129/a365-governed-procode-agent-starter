---
title: "Evidence — teardown → setup round-trip reproducibility"
date: 2026-04-21
categories: [a365, evidence]
tags: [reproducibility, teardown, setup, automation, proof]
excerpt: >-
  Claim: the starter is fully reproducible — wipe everything, re-provision,
  and you land on an identical working state. Here is the captured
  round-trip with per-step outcomes.
---

## Why this post matters

A reference implementation that only works on the first run isn't a
reference — it's a snowflake. The starter's reproducibility test is a
**full round-trip**:

```
teardown-environment.ps1   →   (empty tenant)   →   setup-environment.ps1
```

If both halves succeed and the resulting environment passes the smoke
test, the starter is reproducible. Captured outcomes live in
[`docs/evidence/round-trip.md`](../../../docs/evidence/round-trip.md).

## What was tested

1. **Teardown** — remove the resource group, Entra client app, blueprint,
   agent identity, role assignments, and local env files.
2. **Re-provision** — run `setup-environment.ps1` from scratch.
3. **Smoke test** — start the host, send `hello` via Playground, confirm
   a turn completes and OTel spans emit.

Each step's outcome (✅ / ⚠️ / ❌ with notes) is recorded in the
canonical evidence doc.

## Key concepts in five bullets

- **Idempotent setup** — re-running `setup-environment.ps1` after a
  partial teardown is safe; existing resources are reused.
- **Best-effort teardown** — `teardown-environment.ps1` keeps going on
  per-step failures and reports a summary, so a half-broken state
  still gets cleaned up.
- **Confirmation guardrail** — teardown requires `-SkipConfirmation`
  for unattended runs to avoid accidental wipes.
- **Smoke test is part of the loop** — `scripts/smoke-test.ps1` exits
  non-zero on a failed turn so you can wire round-trips into CI.
- **Generated config tells the story** — `a365.generated.config.json`
  is regenerated end-to-end on each pass; comparing two runs shows
  only IDs change, not shape.

## Try it yourself

```pwsh
# 1. Tear it all down (irreversible — read the prompts).
pwsh -NoProfile -File scripts/teardown-environment.ps1 -SkipConfirmation

# 2. Re-provision from an empty state.
pwsh -NoProfile -File scripts/setup-environment.ps1

# 3. Refresh the bearer token and run the smoke test.
pwsh -NoProfile -File .vscode/scripts/refresh-bearer-token.ps1
pwsh -NoProfile -File scripts/smoke-test.ps1
```

If any step fails, capture its console output and the relevant section
of `a365.generated.config.json`, then open
[`TROUBLESHOOTING.md`](../../../TROUBLESHOOTING.md) — the common
failure modes have one-line fixes.

## Where to go from here

You've reached the end of the series. From here:

- **Build on the starter** — swap `agent.py` for your own agent
  implementing `agent_interface.py`. Hosting, identity, and observability
  stay as-is.
- **Add a tool** — register a new MCP server; no host changes needed.
- **Re-run the round-trip** — anytime you change setup or teardown,
  prove it still reproduces.

## Go deeper

- Canonical evidence: [`docs/evidence/round-trip.md`](../../../docs/evidence/round-trip.md)
- Setup walkthrough: [`docs/setup-walkthrough.md`](../../../docs/setup-walkthrough.md)
- Smoke test script: [`scripts/smoke-test.ps1`](../../../scripts/smoke-test.ps1)

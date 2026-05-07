---
section: Architecture Decisions
---
# ADR 0001 — Polyglot Pester + pytest test strategy

- **Status:** Accepted (May 7, 2026)
- **Context:** [Architecture review](../../.copilot-tracking/research/subagents/2026-05-07/) flagged the dual test runtime as a maintenance risk.

## Decision

Keep both pytest (Python) and Pester 5.7.1 (PowerShell). Run them as two separate jobs in `.github/workflows/ci.yml`. Do not consolidate.

## Scope split

| Suite  | What it tests                                                    | Style                              |
|--------|------------------------------------------------------------------|------------------------------------|
| pytest | `agent.py`, `token_cache.py`, `scripts/build_manifests.py`, doc-link integrity, posts↔docs parity | Behavioural — exercises real code paths with mocks |
| Pester | `setup-environment.ps1`, `smoke-test.ps1`                        | Contract / lint — regex assertions on parameter surface, GA-channel pinning, structural invariants |

Pester intentionally does **not** execute the scripts end-to-end; that's `smoke-test.ps1` running against a live tenant.

## Why

- Pester is the only credible PowerShell test framework. Replacing it with pytest+`subprocess.run("pwsh", ...)` would assert on stdout strings instead of structured PowerShell objects — a downgrade.
- The PowerShell surface (`setup-environment.ps1`, `provision-second-instance.ps1`, `refresh-observability-token.ps1`, etc.) is real and growing. It is the operator's primary interface.
- CI cost is negligible: pytest ~1.5s, Pester ~1s, run in parallel.
- Contributors who change `.ps1` already know PowerShell; contributors who change `agent.py` already know pytest.

## Rejected alternatives

- **Consolidate to pytest only:** loses native PowerShell idioms in PowerShell tests for marginal "one toolchain" benefit.
- **Invest in deep Pester mocks (`Mock az { ... }`):** scripts are Azure-bound integration glue, not pure logic. Mocking deeply enough to be meaningful is multi-day work for tests inferior to a real `smoke-test.ps1` run.

## Triggers to revisit

- PowerShell surface grows past ~1500 lines.
- New scripts have non-trivial pure logic worth unit-testing in isolation.

Either trigger should prompt elevating Pester from contract tests to behavioural tests with mocks.

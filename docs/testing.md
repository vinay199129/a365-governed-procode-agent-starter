# Testing strategy

This repo has two independent loops: **tenant lifecycle** (rare, side-effecting PowerShell) and **code lifecycle** (every change, fast unit tests). The smoke test bridges them.

```
┌─────────────────────────────────────────────────────────────────────┐
│ Tenant lifecycle  (run rarely, side-effecting)                      │
│                                                                     │
│   setup-environment.ps1  ──►  produces tenant + blueprint + .env   │
│            ▲                                                        │
│            │ guarded by                                             │
│            │                                                        │
│   setup-environment.Tests.ps1  (Pester 5, no live calls)            │
└─────────────────────────────────────────────────────────────────────┘
                          │
                          │ tenant exists, F5 starts host on :3978
                          ▼
┌─────────────────────────────────────────────────────────────────────┐
│ Bridge  (one HTTP probe, exit 0/1)                                  │
│                                                                     │
│   smoke-test.ps1  ──►  POST /api/messages, assert 2xx               │
│            ▲                                                        │
│            │ guarded by                                             │
│            │                                                        │
│   smoke-test.Tests.ps1  (Pester 5, asserts payload shape)           │
└─────────────────────────────────────────────────────────────────────┘
                          │
                          │ contract held, code changes are next
                          ▼
┌─────────────────────────────────────────────────────────────────────┐
│ Code lifecycle  (run on every change, no tenant needed)             │
│                                                                     │
│   tests/test_agent_interface.py    ABC contract                     │
│   tests/test_token_cache.py        cache semantics                  │
│   tests/test_tooling_manifest.py   manifest schema shape            │
└─────────────────────────────────────────────────────────────────────┘
```

## What each layer guarantees

| Layer | File | What it proves | Side effects |
|---|---|---|---|
| Python unit | [tests/test_agent_interface.py](../tests/test_agent_interface.py) | Any class implementing `AgentInterface` is host-compatible. ABC rejects partial impls. | None |
| Python unit | [tests/test_token_cache.py](../tests/test_token_cache.py) | `(tenant_id, agent_id)` namespacing; cache miss returns `None`; overwrite works. | None |
| Python unit | [tests/test_tooling_manifest.py](../tests/test_tooling_manifest.py) | `ToolingManifest.json` has required fields, unique server names, A365 audience + URL prefix, `McpServers.<X>.All` scope pattern. | None |
| Pester | [scripts/setup-environment.Tests.ps1](../scripts/setup-environment.Tests.ps1) | Parameter contract + GA-channel pinning regression guard (no `--prerelease`). | None |
| Pester | [scripts/smoke-test.Tests.ps1](../scripts/smoke-test.Tests.ps1) | Activity-builder produces the exact payload shape the host expects (tenant id, agentic app id, message text, channel data). | None |
| HTTP probe | [scripts/smoke-test.ps1](../scripts/smoke-test.ps1) | Live host on `:3978` accepts a `message` activity and returns 2xx. Exit code 0 / 1. | One real HTTP call to localhost |

## How to run

### Every code change (fast, ~7s total)

```powershell
uv run pytest tests/ -q
Invoke-Pester scripts/*.Tests.ps1 -Output Normal
```

### After F5 (live host probe)

```powershell
.\scripts\smoke-test.ps1
# or with custom payload:
.\scripts\smoke-test.ps1 -Message "what time is it?" -HostUrl "http://localhost:3978"
```

### Full sweep (before commit)

```powershell
uv run python -c "import agent_interface, token_cache, agent_msaf"   # import sanity
uv run pytest tests/ -q                                              # python units
Invoke-Pester scripts/*.Tests.ps1                                    # pester units
# (only if F5 host is running)
.\scripts\smoke-test.ps1
```

## What is *not* tested here (yet)

These need a live tenant and so are deferred to the round-trip evidence script (see [docs/evidence/round-trip.md](evidence/round-trip.md)):

- Real OBO token exchange via `GraphAgenticHandler`
- Real MCP tool invocation against `agent365.svc.cloud.microsoft`
- Observability span export to the A365 portal
- Notifications round-trip
- AI teammate (Frontier-gated) tier

## Adding a new test

- **Code change → Python test.** Drop a file in `tests/` named `test_*.py`. Pytest auto-discovers via `[tool.pytest.ini_options]` in `pyproject.toml`.
- **Script change → Pester test.** Drop a file next to the script named `<script-name>.Tests.ps1`.
- **New manifest field?** Add it to `REQUIRED_SERVER_FIELDS` in `tests/test_tooling_manifest.py`.
- **New agent implementation?** Just inherit from `AgentInterface`. The contract test will catch missing methods at instantiation time.

# Code Walkthrough — From F5 to a Response

A stage-by-stage trace of what happens when a user sends a message to the agent. Pair this with [setup-walkthrough.md](setup-walkthrough.md) (which covers what `setup-environment.ps1` provisions) and [design.md](design.md) (architecture overview).

> **Read this when:** you're new to the codebase and want to understand request flow before touching any file. Each stage cites the source file and line so you can open it side by side.

---

## High-level request flow

```
                    ┌──────────────────────┐
                    │  User in Playground  │
                    │  / Teams / Outlook   │
                    └──────────┬───────────┘
                               │ POST /api/messages
                               ▼
       ┌──────────────────────────────────────────────────┐
       │  aiohttp endpoint  (Microsoft 365 Agents SDK)     │
       │  → CloudAdapter routes the activity               │
       └──────────────────────────┬────────────────────────┘
                                  │
                                  ▼
       ┌──────────────────────────────────────────────────┐
       │  GenericAgentHost.on_message     [host_agent_     │
       │                                   server.py:228]  │
       │   1. Extract tenant_id + agent_id from recipient  │
       │   2. Open OTel BaggageBuilder scope               │
       │   3. (if agentic) exchange + cache OBS token      │
       │   4. Send "Got it…" + start typing-indicator loop │
       └──────────────────────────┬────────────────────────┘
                                  │
                                  ▼
       ┌──────────────────────────────────────────────────┐
       │  OpenAIAgentWithMCP.process_user_message          │
       │                                  [agent.py:348]   │
       │   5. Log activity.from_property identity          │
       │   6. setup_mcp_servers (auth ladder, see below)   │
       │   7. dataclasses.replace → personalize prompt     │
       │   8. Runner.run(personalized_agent, message)      │
       └──────────────────────────┬────────────────────────┘
                                  │
                                  ▼
       ┌──────────────────────────────────────────────────┐
       │  OpenAI Agents SDK Runner loop                    │
       │   LLM → (maybe tool call → MCP server → ...) →    │
       │   final_output                                    │
       │                                                   │
       │   Every step auto-emits OTel spans because        │
       │   OpenAIAgentsTraceInstrumentor.instrument() is   │
       │   active. Spans inherit tenant_id/agent_id from   │
       │   step 2's baggage scope.                         │
       └──────────────────────────┬────────────────────────┘
                                  │ final_output
                                  ▼
       ┌──────────────────────────────────────────────────┐
       │  Back in on_message:                              │
       │   9. Cancel typing loop                           │
       │  10. context.send_activity(response)              │
       └──────────────────────────────────────────────────┘
```
---

## Pattern: super-agent / agent-to-agent (A2A) delegation

A *super-agent* fronts a user turn and delegates sub-tasks to one or more
specialist agents. A365 makes this safe by giving each delegate its own
blueprint-derived identity and by carrying that identity end-to-end on the wire.

```
   User turn                                 Delegate(s)
   ─────────                                 ────────────
       │
       ▼
   ┌─────────────────────────┐      Tier-3 OBO call
   │  super-agent              ├───────────────────┐
   │  blueprint A              │                  ▼
   │  identity "BookingBot"    │   ┌─────────────────┐
   │                           │   │ specialist     │
   │  Decides: "this is a      │   │ blueprint B    │
   │  travel + calendar req."  │   │ "TravelAgent"  │
   │                           │   └─────────┬──────┘
   │  Calls TravelAgent +      │             │
   │  CalendarAgent in         │             ▼
   │  parallel.                │         own MCP allow-list
   └─────────────────────────┘         own OTel spans
```

**What A365 contributes to this pattern**

| Concern | Single agent | Super-agent + delegates |
|---|---|---|
| Identity per call | One agent identity | Each delegate has its own blueprint + identity |
| Authorization | Blueprint A's allow-list | Each delegate enforces *its own* blueprint allow-list — super-agent cannot smuggle in extra scopes |
| Audit attribution | All spans tagged with agent A | Each delegate emits its own spans tagged with delegate's `agent_id` |
| Revocation | Disable blueprint A | Disable any blueprint independently — finer-grained kill switch |

**Wiring it in this repo (sketch)**

The host (`host_agent_server.py`) loads one `AgentInterface` today. To run a
super-agent pattern you have two clean options:

1. **In-process delegates.** Compose multiple `AgentInterface` instances inside a
   wrapper that itself implements `AgentInterface`. The wrapper picks which
   delegate to call based on intent classification, then forwards `context` so
   each delegate's own `auth.exchange_token(...)` mints a token under *its* blueprint.
   This is the simplest path — nothing on the network changes; only the
   `process_user_message` body fans out.
2. **Out-of-process delegates (true A2A).** Each delegate runs as its own
   hosted agent (own blueprint, own UPN). The super-agent calls them as
   tools — either via A365 MCP if the delegate is exposed that way, or via
   plain HTTPS with an agentic-identity token in the Authorization header.
   Pick this when delegates are owned by different teams or need independent
   deploy cadence.

**Sibling LLM frameworks**

The `AgentInterface` contract is framework-neutral. [agent.py](../agent.py) uses
the OpenAI Agents SDK; [agent_msaf.py](../agent_msaf.py) is a parallel
implementation that swaps in the **Microsoft Agent Framework**. A super-agent
can freely mix delegates: e.g. a planning loop in MSAF that fans out to
specialist OpenAI Agents SDK delegates. The A365 governance plane (blueprint,
identity, MCP allow-list, OTel exporter) is identical regardless.
---

## Stage A — Process boot ([start_with_generic_host.py](../start_with_generic_host.py))

A 30-line launcher. Imports the agent class and the host factory, then calls `create_and_run_host(OpenAIAgentWithMCP)`. The point of keeping it tiny is that **the host doesn't know which LLM you're using** — the host accepts any class that satisfies `AgentInterface`.

## Stage B — The contract ([agent_interface.py](../agent_interface.py))

Three abstract methods every agent must implement:

| Method | Called when | Returns |
|---|---|---|
| `initialize()` | Once, at host boot | `None` |
| `process_user_message(message, auth, auth_handler_name, context)` | Per user turn | `str` |
| `cleanup()` | At shutdown | `None` |

`check_agent_inheritance()` enforces this at startup. Swap in LangChain, Semantic Kernel, or your own — the host doesn't care, as long as the contract holds.

## Stage C — Host construction ([host_agent_server.py:147-198](../host_agent_server.py))

`GenericAgentHost.__init__` wires up the M365 Agents SDK:

| Component | Purpose |
|---|---|
| `MemoryStorage` | In-process state store for conversations |
| `MsalConnectionManager` | MSAL-backed connections (for agentic OBO token exchange) |
| `CloudAdapter` | Bot Framework adapter — speaks the activity protocol |
| `Authorization` | Wraps the connection manager to mint downstream tokens (MCP, OBS) |
| `AgentApplication[TurnState]` | High-level handler registry — `app.message(...)`, `app.activity(...)` |
| `SafeAgentNotification` | Wrapper that swallows `ValueError` for unparseable invokes (prevents 501) |

It also reads `AUTH_HANDLER_NAME` from env. **Latent defect:** nothing currently writes this var, so the agentic-auth path silently degrades. Tracked in [TROUBLESHOOTING.md](../TROUBLESHOOTING.md#auth_handler_name-is-not-set-when-use_agentic_authtrue).

## Stage D — Handler registration ([host_agent_server.py:_setup_handlers](../host_agent_server.py))

The host registers four handler families:

```
AgentApplication
├── /help, conversation_update("membersAdded")  →  static welcome
├── activity("installationUpdate")              →  hire / farewell message
├── activity("message")                         →  main turn handler  (Stage E)
└── activity("invoke")                          →  agent/notification (email, Word comment)
```

## Stage E — A user sends "hello" ([on_message](../host_agent_server.py))

This is the meat. Six things happen, in order:

### 1. Extract identifiers from the activity

```python
tenant_id = context.activity.recipient.tenant_id
agent_id  = context.activity.recipient.agentic_app_id
```

`agentic_app_id` is the `AgenticAppId` your setup script wrote into `a365.generated.config.json`. The platform stamps it on every activity addressed to your agent.

### 2. Open an OTel baggage scope

```python
with BaggageBuilder().tenant_id(tenant_id).agent_id(agent_id).build():
    ...
```

Every span emitted inside this `with` block carries `tenant_id` + `agent_id` as OTel baggage. The A365 backend uses these to partition multi-tenant trace data. **This is how the exporter knows which agent's traces it's sending.**

### 3. (Conditional) token exchange for observability

```python
if self.auth_handler_name:
    exaau_token = await self.agent_app.auth.exchange_token(
        context, scopes=get_observability_authentication_scope(),
        auth_handler_id=self.auth_handler_name,
    )
    cache_agentic_token(tenant_id, agent_id, exaau_token.token)
```

The **agentic OBO path**. Takes the user's delegated token, exchanges it for an *agentic* token (acting as the blueprint identity) scoped to the OBS endpoint, and caches it in [token_cache.py](../token_cache.py) for the OTel exporter to pick up.

In Playground mode `auth_handler_name` is `None`, so this whole block is skipped — and `agent.py:token_resolver` falls back to the env-supplied `OBS_S2S_TOKEN`.

### 4. Acknowledgment + typing indicator

```python
await context.send_activity("Got it — working on it…")    # discrete Teams message
await context.send_activity(Activity(type="typing"))       # initial indicator

async def _typing_loop():
    while True:
        await asyncio.sleep(4)                              # re-send every 4s
        await context.send_activity(Activity(type="typing"))

typing_task = asyncio.create_task(_typing_loop())          # background refresh
```

Typing indicators expire after ~5s in Teams; the loop refreshes them so the "…" stays visible while the LLM works.

### 5. Hand the message to the agent

```python
response = await self.agent_instance.process_user_message(
    user_message, self.agent_app.auth, self.auth_handler_name, context,
)
```

### 6. Send the response, cancel the typing loop

```python
await context.send_activity(response)
typing_task.cancel()
```

## Stage F — Agent processes the turn ([agent.py:process_user_message](../agent.py))

Four things, in order:

1. **Log caller identity** from `activity.from_property` — `name`, `id`, `aad_object_id`. (No API call; the platform supplies this on every activity.)
2. **Call `setup_mcp_servers(...)`** *before* cloning the agent — MCP setup *replaces* `self.agent` with a new `Agent` that has tool servers attached. Cloning first would lose the tools.
3. **Personalize instructions** with the user's display name via `dataclasses.replace(self.agent, instructions=...)` — a per-turn local copy, not a mutation of `self.agent`, so concurrent turns don't trample each other.
4. **Run the agent** via `Runner.run(starting_agent=personalized_agent, input=message, context=context)`. The OpenAI Agents SDK loop: LLM → tool call → LLM → … → final output.

## Stage G — MCP server setup ([agent.py:setup_mcp_servers](../agent.py))

The four-priority auth ladder. **First match wins.**

```
                    ┌────────────────────────────────────┐
                    │  setup_mcp_servers entered         │
                    └─────────────────┬──────────────────┘
                                      │
              ┌───────────────────────┴───────────────────────┐
              │                                               │
              ▼ Priority 1                                    │
        USE_AGENTIC_AUTH=true ?  ─── yes ──▶ add_tool_servers │
              │ no                            (no auth_token; │
              │                                handler mints  │
              ▼                                OBO token)     │
        BEARER_TOKEN set ?       ─── yes ──▶ add_tool_servers │
              │ no                            (auth_token=    │
              │                                bearer_token)  │
              ▼ Priority 3                                    │
        auth_handler_name set ?  ─── yes ──▶ add_tool_servers │
              │ no                            (handler-only)  │
              │                                               │
              ▼ Priority 4                                    │
        ┌───────────────────────┐                             │
        │ Bare LLM mode         │                             │
        │ (no MCP tools)        │                             │
        │ Logs a warning        │                             │
        └───────────────────────┘                             │
                                                              │
        ┌───────────────────────┐                             │
        │ Exception during      │                             │
        │ MCP setup?            │ ──▶ if dev + skip flag:     │
        │                       │     log + bare LLM          │
        │                       │     else: raise (fail fast) │
        └───────────────────────┘                             │
```

Why the strict priority? Silent fallback to bare LLM in production is a security risk — the MCP servers are part of the **governance boundary**. The escape hatch (`ENVIRONMENT=development AND SKIP_TOOLING_ON_ERRORS=true`) requires both flags explicitly.

## Stage H — Observability wiring ([agent.py:_setup_observability](../agent.py))

Called once at agent construction:

```python
configure(
    service_name=os.getenv("OBSERVABILITY_SERVICE_NAME", "openai-sample-agent"),
    service_namespace=os.getenv("OBSERVABILITY_SERVICE_NAMESPACE", "agent365-samples"),
    token_resolver=self.token_resolver,
)
OpenAIAgentsTraceInstrumentor().instrument()
```

`configure()` registers the A365 exporter as an OTel `SpanProcessor` on the global tracer provider. The `token_resolver` is a callback the exporter invokes to mint auth headers on demand.

`OpenAIAgentsTraceInstrumentor().instrument()` patches the OpenAI Agents SDK to emit spans for every `Runner.run`, every tool call, every LLM inference. **Zero application code changes** — your agent code just produces OTel spans automatically.

### Token resolution order (`token_resolver`)

```
1. get_cached_agentic_token(tenant_id, agent_id)   ← from Stage E.3 (real auth)
   ↓ (None)
2. os.getenv("OBS_S2S_TOKEN")                       ← from refresh-observability-token.ps1 (local-dev)
   ↓ (None)
3. return None                                      ← exporter drops the span
```

## Stage I — Bearer-token plumbing ([local_authentication_options.py](../local_authentication_options.py))

`LocalAuthenticationOptions.from_environment()` reads `BEARER_TOKEN` (the **un-prefixed** runtime name) and wraps it in a dataclass. Used by Stage G Priority 2.

The token itself is minted by [.vscode/scripts/refresh-bearer-token.ps1](../.vscode/scripts/refresh-bearer-token.ps1) (interactive device-code flow). The M365 Agents Toolkit re-exposes `SECRET_BEARER_TOKEN` as `BEARER_TOKEN` per [m365agents.playground.yml](../m365agents.playground.yml) — see the env-flow table in [design.md](design.md#how-env-variables-flow-into-the-running-agent).

---

## What you should be able to answer after this

- *"Where does the agent learn `tenant_id` and `agent_id`?"* → Stage E.1 (`activity.recipient`).
- *"How do OTel spans get the right tenant attached?"* → Stage E.2 (BaggageBuilder).
- *"Why is `agent.py` reading `BEARER_TOKEN` and not `SECRET_BEARER_TOKEN`?"* → Stage I + the env-flow table in design.md.
- *"What happens if MCP setup throws in production?"* → Stage G — fail-fast unless dev mode + explicit opt-in.
- *"How is the agent's prompt personalized per user without state mutation?"* → Stage F.3 (`dataclasses.replace`).

For what gets provisioned in Azure / Entra to make all of this work, continue to [setup-walkthrough.md](setup-walkthrough.md).

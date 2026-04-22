---
title: "Architecture & design of the pro-code agent starter"
date: 2026-04-16
categories: [a365, architecture]
tags: [openai-agents-sdk, mcp, host-pattern, design]
excerpt: >-
  A diagram-led tour of how the starter is wired together — the generic host,
  the pluggable agent interface, MCP tools, and the A365 observability layer.
---

## Why this post matters

The starter is small but it intentionally separates concerns so you can
swap pieces without rewriting the rest:

- the **host** owns transport, activity routing, and observability;
- the **agent** owns reasoning and tool use;
- **MCP servers** own tool implementations (Mail, Calendar);
- **A365** owns identity and governance — *outside* the process.

Understanding those boundaries makes the [code walkthrough]({% post_url 2026-04-18-code-walkthrough %})
much easier to follow.

## The four moving parts

```
start_with_generic_host.py        ← entry point: builds + runs the host
        │
        ▼
host_agent_server.py              ← GenericAgentHost: aiohttp + CloudAdapter
        │  on_message(activity)
        ▼
agent.py  (implements agent_interface.py)
        │  uses → OpenAI Agents SDK
        │  uses → MCP servers (Mail, Calendar)
        ▼
Azure OpenAI / OpenAI    +    Microsoft Agent 365 (governance + telemetry sink)
```

Why this shape?

- **`agent_interface.py`** is an `abc.ABC` so you can drop in a
  LangChain/Semantic Kernel agent without touching the host.
- **`host_agent_server.py`** is the only file that knows about
  aiohttp, the M365 Agents SDK `CloudAdapter`, and OTel setup — so
  hosting concerns don't leak into the agent.
- **`token_cache.py` + `local_authentication_options.py`** isolate the
  S2S / observability token dance so the agent code stays clean.

## Key concepts in five bullets

- **Generic host pattern** — one host, many agents. Same transport,
  same observability, swappable reasoning.
- **Abstract agent interface** — `agent_interface.py` defines the
  contract; `agent.py` is one implementation.
- **MCP tool registration** — tools are discovered from MCP servers
  at startup, not hard-coded.
- **Graceful degradation** — if the OpenAI SDK or MCP servers are
  unavailable, the host falls back to a "bare LLM" mode so you can
  still smoke-test.
- **A365 is a sidecar concern** — the agent code never imports A365;
  governance is configured at the *identity* and *blueprint* layer.

## Try it yourself

Read the architecture doc with the source files open in a split editor:

```pwsh
# Open the design doc and the four core files side by side.
code docs/design.md
code start_with_generic_host.py
code host_agent_server.py
code agent_interface.py
code agent.py
```

Then trace one scenario yourself: *"a user sends `hello` — which file
runs first, and where does the response originate?"* The
[code walkthrough post]({% post_url 2026-04-18-code-walkthrough %})
has the answer if you get stuck.

## Go deeper

- Canonical doc: [`docs/design.md`](../../../docs/design.md)
- Microsoft 365 Agents SDK: <https://aka.ms/teams-toolkit>
- OpenAI Agents SDK for Python: <https://github.com/openai/openai-agents-python>

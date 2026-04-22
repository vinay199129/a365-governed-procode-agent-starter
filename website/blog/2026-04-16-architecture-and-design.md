---
slug: architecture-and-design
title: Architecture & design of the pro-code agent starter
authors: starter-team
tags: [architecture, design, mcp]
date: 2026-04-16
---

A diagram-led tour of how the starter is wired together — the generic host,
the pluggable agent interface, MCP tools, and the A365 observability layer.

<!-- truncate -->

## Why this post matters

The starter is small but it intentionally separates concerns so you can
swap pieces without rewriting the rest:

- the **host** owns transport, activity routing, and observability;
- the **agent** owns reasoning and tool use;
- **MCP servers** own tool implementations (Mail, Calendar);
- **A365** owns identity and governance — *outside* the process.

Understanding those boundaries makes the [code walkthrough](./code-walkthrough.md)
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

## Key concepts in five bullets

- **Generic host pattern** — one host, many agents.
- **Abstract agent interface** — `agent_interface.py` defines the contract; `agent.py` is one implementation.
- **MCP tool registration** — tools come from MCP servers, not hard-coded imports.
- **Graceful degradation** — falls back to bare-LLM mode if MCP is unavailable.
- **A365 is a sidecar concern** — agent code never imports A365.

## Try it yourself

```pwsh
code docs/design.md
code start_with_generic_host.py
code host_agent_server.py
code agent_interface.py
code agent.py
```

## Go deeper

- Canonical doc: [Architecture: Design](/docs/design)
- Microsoft 365 Agents SDK: <https://aka.ms/teams-toolkit>
- OpenAI Agents SDK for Python: <https://github.com/openai/openai-agents-python>

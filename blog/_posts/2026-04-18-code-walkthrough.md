---
title: "Code walkthrough — from F5 to a response"
date: 2026-04-18
categories: [a365, code]
tags: [request-flow, openai-agents-sdk, mcp, observability]
excerpt: >-
  Press F5 in VS Code. A user types a message in Microsoft 365 Agents
  Playground. What runs, in what order, and which file owns each stage?
  This post traces the full path.
---

## Why this post matters

The fastest way to feel comfortable in a new codebase is to **trace one
real request end to end**. This post is the narrated version of
[`docs/code-walkthrough.md`](../../../docs/code-walkthrough.md), which
cites file + line for every stage. Open both side by side.

## The request, stage by stage

```
User in Playground  ──POST /api/messages──▶  aiohttp endpoint
                                                  │
                                                  ▼
                                       CloudAdapter (M365 Agents SDK)
                                                  │
                                                  ▼
                                     GenericAgentHost.on_message
                                          (host_agent_server.py)
                                                  │
                                  log activity.from_property fields
                                  inject display name into system prompt
                                                  │
                                                  ▼
                                    Agent.run_turn(activity, prompt)
                                              (agent.py)
                                                  │
                              OpenAI Agents SDK + registered MCP tools
                                                  │
                                                  ▼
                                Response activity ── back through adapter
                                                  │
                                                  ▼
                              OTel spans exported to A365 ingest endpoint
```

## Key concepts in five bullets

- **`activity.from_property` is free** — `id`, `name`, `aad_object_id`
  are populated on every message; no Graph call needed.
- **The host injects identity** — the user's display name is added to
  the system prompt so the LLM can personalise responses without the
  agent code asking for it.
- **Tools are MCP, not Python imports** — Mail and Calendar are external
  MCP servers. Adding a new tool means registering a new MCP server,
  not editing `agent.py`.
- **Spans wrap the turn** — one root span per `on_message`, child spans
  per tool call. Even when the A365 ingest returns 403 (pre-Frontier),
  the spans still emit locally and you can observe them via the OTel
  console exporter.
- **Failure modes are explicit** — token expiry, missing MCP server,
  and bare-LLM fallback are all logged with actionable text.

## Try it yourself

```pwsh
# 1. Refresh the short-lived bearer token (4-min TTL).
pwsh -NoProfile -File .vscode/scripts/refresh-bearer-token.ps1

# 2. In VS Code: open the Microsoft 365 Agents Toolkit panel.
#    Press F5 → "Debug in Microsoft 365 Agents Playground".

# 3. In the Playground browser tab, send: "hello"
#    Watch the integrated terminal. You should see, in order:
#      - "Activity received" with from_property fields
#      - "System prompt augmented for <Display Name>"
#      - OpenAI Agents SDK turn logs
#      - OTel span export attempt (200 with Frontier, 403 without)
```

Then set a breakpoint at the top of `GenericAgentHost.on_message` in
[`host_agent_server.py`](../../../host_agent_server.py) and step through
one turn. Five minutes there is worth an hour of reading.

## Go deeper

- Canonical doc: [`docs/code-walkthrough.md`](../../../docs/code-walkthrough.md)
- Architecture overview: [`docs/design.md`](../../../docs/design.md) and the
  [architecture post]({% post_url 2026-04-16-architecture-and-design %})
- Troubleshooting: [`TROUBLESHOOTING.md`](../../../TROUBLESHOOTING.md)

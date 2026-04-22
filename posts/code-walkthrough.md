---
slug: code-walkthrough
title: Code walkthrough — from F5 to a response
authors: starter-team
tags: [code, request-flow, observability]
date: 2026-04-18
---

Press F5 in VS Code. A user types a message in Microsoft 365 Agents
Playground. What runs, in what order, and which file owns each stage?

<!-- truncate -->

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

- **`activity.from_property` is free** — `id`, `name`, `aad_object_id` populated on every message.
- **The host injects identity** — display name is added to the system prompt.
- **Tools are MCP, not Python imports** — add a tool by registering an MCP server.
- **Spans wrap the turn** — even when ingest 403s, spans still emit locally.
- **Failure modes are explicit** — token expiry, missing MCP, bare-LLM fallback all logged.

## Try it yourself

```pwsh
pwsh -NoProfile -File .vscode/scripts/refresh-bearer-token.ps1
# Then in VS Code: F5 → Debug in Microsoft 365 Agents Playground.
# Send "hello" and watch the integrated terminal.
```

Set a breakpoint at the top of `GenericAgentHost.on_message` and step through
one turn. Five minutes there is worth an hour of reading.

## Go deeper

- Canonical doc: [Code walkthrough](docs.html?doc=code-walkthrough)
- [Architecture overview](docs.html?doc=design)
- [Troubleshooting](docs.html?doc=troubleshooting)

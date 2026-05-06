---
slug: what-is-agent-365
title: What is Microsoft Agent 365 — and why pro-code?
authors: starter-team
tags: [a365, concepts]
date: 2026-04-15
---

A concept-first tour of Microsoft Agent 365 (A365): what problem it solves,
what changes for pro-code agents, and what works today vs. what is gated
behind the Frontier preview.

<!-- truncate -->

## Why this post matters

Before A365, building a custom (pro-code) agent for an enterprise meant
hand-rolling identity, governance, observability, lifecycle, and the
plumbing to make all of those visible to admins. **Agent 365 is the
governance and identity layer that Microsoft is putting around agents** —
so your code can focus on the agent's job, not the paperwork.

## Key concepts in five bullets

- **Blueprint** — an Entra-registered governance anchor. It declares the
  scopes, posture, and policy your agents inherit.
- **Agent Identity** — a real Entra principal (with a tenant UPN) that
  represents the agent. Users can chat with it, mention it, see it in
  the directory.
- **Agent Instance** — each running deployment of your agent. Instances
  *inherit* the blueprint posture byte-for-byte (no per-instance config
  drift). See the [multi-instance inheritance evidence post](learning-series.html?post=evidence-multi-instance-inheritance).
- **Observability** — OpenTelemetry spans flow to the A365 backend so
  admins can audit what the agent did, on whose behalf.
- **Pro-code, not Copilot Studio** — A365 is SDK-first. You bring your
  own framework (OpenAI Agents SDK, LangChain, Semantic Kernel, …)
  and A365 wraps governance around it.

## What works today vs. what is gated

A365 reached **General Availability on May 1, 2026**. Microsoft frames the
platform as **four incremental capability tiers** — Register → Observability →
Work IQ → **AI teammate** — and you adopt only the ones your scenario needs.
The AI teammate tier (own UPN, real mailbox, Teams presence, `@mention`
anywhere) is the only one still gated to the
[Frontier program](https://adoption.microsoft.com/copilot/frontier-program/) at GA.

| Capability | Tier | Works on a normal GA tenant? |
| --- | --- | --- |
| `a365` CLI + A365 Python SDK | — | Yes |
| AI-guided setup ([aka.ms/agent365enable](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/get-started)) | — | Yes |
| Blueprint + Agent Identity provisioning (Entra) | Register | Yes |
| Multi-instance inheritance | Register | Yes |
| OTel exporter emits spans | Observability | Yes |
| Work IQ MCP tools (Mail, Calendar, …) | Work IQ | Yes |
| Spans land in A365 backend | AI teammate | **Frontier-only at GA** |
| Admin Center → Agents view | AI teammate | **Frontier-only at GA** |
| Defender Advanced Hunting on agent telemetry | AI teammate | **Frontier-only at GA** |
| `@mention` agent in Teams / Outlook / Word | AI teammate | **Frontier-only at GA** |

So the starter is a **correct client-side reference** for the full AI teammate
path, and a **fully working Entra-side governance demo** for everyone — Frontier
or not.

## Try it yourself

```pwsh
# 1. Confirm tooling.
az --version
pwsh --version
python --version  # 3.11+

# 2. Read the concept walkthrough end-to-end (~15 min).
code docs/learning-guide.md
```

When you're ready to actually run something, jump to the
[setup walkthrough post](learning-series.html?post=setup-walkthrough).

## Go deeper

- Canonical doc: [Concepts: Learning guide](docs.html?doc=learning-guide)
- Microsoft Agent 365 developer docs: <https://learn.microsoft.com/en-us/microsoft-agent-365/developer/>
- Frontier preview program: <https://adoption.microsoft.com/copilot/frontier-program/>

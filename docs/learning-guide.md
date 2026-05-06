# A365 Learning Guide

A concept-first walkthrough of **Microsoft Agent 365 (A365)** using this starter as a
working reference. Every concept links to the official Microsoft documentation and to
the exact file in this repo where it is applied.

> **Audience:** Engineers new to A365 who want to understand *what* the platform does,
> *why* it exists, and *how* a pro-code agent participates in it.
>
> **Not a tutorial.** For setup and run instructions, see [README.md](../README.md).
> For the delivery scope and gap analysis, see [project-scope.md](project-scope.md).
>
> **GA status (May 2026 onward).** A365 went **General Availability on May 1, 2026**.
> Microsoft now describes the platform as four incremental capability tiers — **Register →
> Observability → Work IQ → AI teammate** — and you adopt only the tiers your scenario
> needs (see §1.5 below).
>
> **What works on any GA-licensed tenant:** the **A365 SDK** (PyPI), the **`a365` CLI**, the
> **AI-guided setup** at [aka.ms/agent365enable](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/get-started),
> blueprint + agent-identity provisioning, multi-instance inheritance, the OTel exporter,
> and Work IQ MCP tools. Everything in tiers Register / Observability / Work IQ.
>
> **What still requires the [Frontier program](https://adoption.microsoft.com/copilot/frontier-program/) at GA:** the **AI teammate** tier — own UPN with a real mailbox, Teams presence,
> directory entry, and `@mention` everywhere. This is *not* a pre-GA wait; AI teammate is
> deliberately Frontier-only at launch. The Admin Center → Agents view, Defender Advanced
> Hunting on agent telemetry, and per-instance compliance readouts ride on top of the
> teammate identity, so they too need Frontier today.
>
> *In this repo:* the starter exercises the AI teammate path end-to-end (UPN, mailbox
> resolution, Teams-shaped activity flow), so it is a **correct client-side reference**
> ready to light up the moment Frontier — or a future broader rollout — is in place. The
> Entra-side governance and observability paths run fully on any GA tenant; see
> [docs/evidence/multi-instance-inheritance.md](evidence/multi-instance-inheritance.md)
> and [docs/project-scope.md §15](project-scope.md) for the live status of each gap.

---

## 1. What Agent 365 Is (and Is Not)

### The problem A365 exists to solve

Before A365, if you built a custom agent (pro-code, not Copilot Studio), you had to
hand-assemble a lot of plumbing yourself:

- **Identity** — register an Entra app, create a service principal, manage secrets,
  decide whether the agent acts *as itself* or *on behalf of a user*.
- **Permissions** — pick Graph / Teams / Mail scopes, chase admin consent, track which
  agent has which scopes.
- **Tooling** — wire up MCP servers or custom tools per agent, re-authenticate for each
  one.
- **Governance** — there was no central place for an admin to say *"every agent in my
  tenant must follow these rules."*
- **Observability** — bring your own OpenTelemetry stack; Microsoft had no tenant-side
  view of what your agent was doing.
- **Compliance** — DLP, auditing, retention — all DIY.

Each team did it differently. An admin could not answer simple questions like *"how
many agents are running in my tenant, who owns them, what can they touch, and are any
of them misbehaving?"*

**A365's one-line pitch:** *treat an agent as a first-class enterprise identity in
Microsoft 365, governed the same way a user is governed — with one central policy (the
blueprint) that every instance of the agent inherits automatically.*

Everything else in A365 is machinery to deliver that promise.

### The pitch, in Microsoft's words

A365 is positioned by Microsoft as *"the control plane for agents"* — one place for IT
to **observe, govern, and secure every agent** across the tenant, regardless of which
framework, model, or cloud produced it.

| Is | Is Not |
|---|---|
| A **control plane** across Microsoft Entra, Defender, Purview, and the M365 Admin Center | An agent framework — it doesn't run or orchestrate your LLM logic |
| A **set of SDKs, a CLI, and governed MCP servers** any agent can integrate with | A replacement for Copilot Studio, Microsoft Foundry, or the M365 Agents SDK |
| A way to give agents a **real Entra identity** (mailbox, Teams presence, UPN) | A generic service-principal wrapper — agents are first-class principals |
| **Framework-agnostic** — works with Agent Framework, OpenAI Agents SDK, LangChain, Semantic Kernel, Claude Code, and more | Tied to a specific LLM, hosting surface, or cloud |

### The three pillars

A365 breaks the *"treat an agent like a governed user"* promise into **three
pillars**. Each pillar is a distinct capability, surfaced through a distinct tenant
tool — the three things an IT admin cares about for a human employee, applied to
agents.

| Pillar | What A365 delivers | Tenant surface |
|---|---|---|
| **Governance** ([§3](#3-governance-deep-dive-blueprint--inheritance)) | Agents register against an **Entra-registered blueprint** that encodes the allowed posture; every instance inherits it | Microsoft Entra + M365 Admin Center |
| **Security** ([§4](#4-security-deep-dive-agentic-identity--governed-tooling)) | Identity is Entra-backed; data access flows through admin-controlled MCP servers; DLP, Purview, and Defender already understand Entra principals | Microsoft Entra + Purview + Defender |
| **Observability** ([§5](#5-observability-deep-dive-opentelemetry-into-the-tenant)) | Every inference, tool call, and notification is an auditable OpenTelemetry span | M365 Admin Center + Microsoft Defender Advanced Hunting |

#### Pillar 1 — Governance (identity + policy)

- Every agent is registered in **Entra** as a first-class thing — not a random app
  registration.
- A **blueprint** captures the posture: *which Graph scopes, which app roles, which
  MCP tools, which regions, who can provision it*.
- Every deployed **instance** inherits from the blueprint automatically. No
  per-instance consent drift.
- Admin surface: **Microsoft Entra admin center** + **M365 Admin Center → Agents view**.

*Concretely in this repo:* the blueprint is `19bc459c-...`; both `procodeagent` and
`procodeagent2` inherit identically — proven in
[docs/evidence/multi-instance-inheritance.md](evidence/multi-instance-inheritance.md).

#### Pillar 2 — Security (Entra-backed identity + governed tools)

- The agent gets a real **UPN, mailbox, Teams presence, people-card entry** — same
  shape as an employee.
- Tokens carry `idtyp=user` and are marked **agentic**. The agent cannot have a
  password or MFA — it can only authenticate through federated credentials / S2S.
- Data access flows through **governed MCP servers** (Mail, Calendar, Graph) that
  Microsoft audits, instead of the agent holding broad Graph permissions directly.
- Admin surface: **Microsoft Purview** (DLP / retention) + **Microsoft Defender**
  (threat detection).

#### Pillar 3 — Observability (OpenTelemetry into the tenant)

- Every LLM call, every tool invocation, every agent-to-agent message is an
  **auditable OpenTelemetry span**.
- Spans carry baggage identifying *tenant + blueprint + instance*, so the tenant can
  partition by agent.
- Admin surface: **M365 Admin Center** + **Defender Advanced Hunting** (KQL over
  agent telemetry).

*Concretely in this repo:* wired in [agent.py](../agent.py) via
`configure(service_name, service_namespace, token_resolver)` → the A365 exporter
POSTs to `https://agent365.svc.cloud.microsoft/...`.

#### Why three pillars and not one blob

Each pillar maps to a **different Microsoft admin tool that already exists**:

| Pillar | Re-uses | Why that matters |
|---|---|---|
| Governance | Entra | Admins already know how to govern Entra principals |
| Security | Purview + Defender | DLP, audit, threat policies written for users already apply |
| Observability | OTel + Defender Advanced Hunting | Standard OpenTelemetry ingestion, queryable with KQL |

A365 deliberately **does not invent a new admin console**. It plugs agents into the
consoles admins already live in.

**References**

- [Microsoft Agent 365 — product overview](https://www.microsoft.com/en-us/microsoft-agent-365)
- [Microsoft Agent 365 SDK and CLI](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/)
- [Agent 365 SDK overview](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/agent-365-sdk?tabs=python)

### The layering that matters

A365 doesn't replace your agent or its framework — it layers **enterprise capabilities**
on top of both. This is the mental model to hold:

| Layer | Responsibility | Who provides it |
|---|---|---|
| **Enterprise capabilities** | Identity, governance, notifications, observability, tooling | **Agent 365 SDK** |
| **Agent logic** | Prompts, workflows, reasoning | **You** (in this repo: [agent.py](../agent.py)) |
| **LLM orchestrator runtime** | Model invocation + tool orchestration | **Your chosen framework** (in this repo: OpenAI Agents SDK) |
| **Host + activity protocol** | HTTP endpoint, channel adapters, auth plumbing | **Microsoft 365 Agents SDK** ([host_agent_server.py](../host_agent_server.py)) |

> The A365 SDK and the **M365 Agents SDK** are different products despite the similar
> names. The M365 Agents SDK handles hosting and activity protocol; A365 layers
> governance, identity, and compliance on top.

**Reference:** [How is the Agent 365 SDK different?](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/#how-is-the-agent-365-sdk-different)

### 1.5 Pick your tier — the four-tier incremental adoption model

A365 GA is structured as **four capability tiers you adopt incrementally**. You
don't have to take all of A365 to get value — each tier stands alone, and the
[AI-guided setup](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/get-started)
asks which one you want as its first onboarding question.

```
  Tier 1            Tier 2              Tier 3                Tier 4
  Register   →    Observability   →    Work IQ        →    AI teammate
  ---------       --------------       --------------       ---------------
  Blueprint +     OTel spans into      Governed MCP         Own UPN, mailbox,
  agent identity  Defender Advanced    tools (Mail,         Teams presence,
  in Entra        Hunting + Admin      Calendar, SP,        @mention, people
                  Center               Teams, …)            card

  Tenant cost     Tenant cost          Tenant cost          Tenant cost
  Any GA tenant   Any GA tenant        Any GA tenant        ⚠ Frontier-only
```

| Tier | What you get | Smallest scenario it unlocks | This repo |
|---|---|---|---|
| **1. Register** | Blueprint + agent-identity object in Entra; admin-visible registration; per-instance accountability | An admin can answer "who owns this agent and what is it allowed to do?" without touching code | [scripts/setup-environment.ps1](../scripts/setup-environment.ps1) Step 1–3 |
| **2. Observability** | OpenTelemetry exporter + S2S role on the blueprint SP; spans land in Defender Advanced Hunting (Frontier today) | Tenant-wide KQL hunts over agent activity, anomaly detection on tool calls | [agent.py](../agent.py) `_setup_observability()` + [scripts/assign-observability-role.ps1](../scripts/assign-observability-role.ps1) |
| **3. Work IQ** | Governed MCP servers (Mail, Calendar, SharePoint, OneDrive, Teams, Word, User, Copilot, Dataverse) with admin allow-list per server | Agent reads a user's calendar without holding raw `Calendars.Read` against Graph | [ToolingManifest.json](../ToolingManifest.json) (Mail + Calendar today) |
| **4. AI teammate** | Own UPN with real mailbox, Teams presence, directory entry, `@mention` anywhere | Users *talk to* the agent the same way they talk to a colleague — in Teams chat, Outlook reply, Word comment | Wired end-to-end; activates on a Frontier tenant |

**How to choose a tier for *your* scenario:**

- *"I just need an admin record of which agents are running."* → Tier 1.
- *"I need that, plus a way to audit what the agent did."* → Tier 2.
- *"I need that, plus the agent reading from M365 data through governed paths."* → Tier 3.
- *"I want the agent to *be* a colleague — chat in Teams, reply to email, get @mentioned."* → Tier 4 (Frontier today).

The tiers are additive: tier 4 includes everything in tiers 1–3. The starter
exercises all four because the goal is a complete reference; production teams
often ship at tier 1 or tier 2 first and add the rest as scenarios warrant.

#### Adopting a single tier (e.g. Register-only)

The most common minimum-viable adoption is **Register-only** — you want admin
visibility of every agent in the tenant without committing to observability
ingest, governed MCP tools, or a teammate identity yet. To use this repo for
that path:

1. Run [scripts/setup-environment.ps1](../scripts/setup-environment.ps1) as usual — the blueprint and agent identity in Entra are tier 1.
2. Skip the observability exporter: leave `OBS_S2S_TOKEN` unset (or set `OBSERVABILITY_DISABLED=true` in [env/.env.playground](../env/.env.playground)) and the `configure(...)` call in [agent.py](../agent.py) `_setup_observability()` will no-op out.
3. Empty the MCP allow-list: replace [ToolingManifest.json](../ToolingManifest.json) `mcpServers` with `[]` so no governed tools register.
4. Don't enrol the tenant in Frontier — the AI teammate tier stays inactive.

What you get from a Register-only deployment: every agent has an Entra-backed
identity, the M365 Admin Center can list it, and the blueprint is a single
revocation point. What you give up: KQL hunting over agent activity (tier 2),
Mail/Calendar/SharePoint/Teams without raw Graph permissions (tier 3), and
`@mention`-anywhere UX (tier 4).

**Reference:** [Agent 365 — Get started](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/get-started)

---

## 2. Core Concepts

### 2.1 Agent Identity — three components you must know

An A365 agent is not one object; it's **three related Entra objects** working together.

| # | Component | What it is | Analogy |
|---|---|---|---|
| 1 | **Agent blueprint** (agentic application) | Entra app registration that defines required Graph scopes, app roles, auth config, and infrastructure template | The job description |
| 2 | **Agentic app instance** | A deployed instance of the blueprint with its own app ID, service principal, and federated credentials | The employee's badge |
| 3 | **Agentic user** | The runtime identity that appears in the org — UPN, mailbox, Teams presence, people-card entry | The actual person |

**Key characteristics of an agentic user** (different from a regular service principal):

- Marked as **agentic** in the directory; tokens carry `idtyp=user`.
- **Cannot** have traditional credentials — no passwords, passkeys, or MFA factors.
- Must be **created via API** from a parent agent instance (not manually in Entra).
- Has an **immutable parent link** — cannot be re-parented; deleting the parent deletes the user.
- Can be **licensed** (Microsoft 365 E5, Teams Enterprise, Copilot) and gets real mailbox / OneDrive / SharePoint resources.
- Can be **@mentioned** in Teams, Word comments, Outlook — treated like a person.

> Resource provisioning (mailbox, OneDrive) after license assignment usually completes
> in 10–15 minutes but can take up to **24 hours**. Plan for this when validating E2E.

**In this repo**

- Provisioning: [scripts/setup-environment.ps1](../scripts/setup-environment.ps1) drives `a365 setup all`, which creates blueprint → instance → agentic user.
- Config keys: `a365.config.json` defines `agentBlueprintDisplayName`, `agentIdentityDisplayName`, `agentUserPrincipalName`, `agentUserUsageLocation`.
- Runtime caller identity: logged on every turn in [host_agent_server.py](../host_agent_server.py) via `activity.from_property.aad_object_id`.

**Reference:** [Agent 365 Identity](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/identity)

### 2.2 Security Blueprints — the governance anchor

The blueprint is an Entra-registered, IT-approved definition of an agent type. It
encodes:

- Microsoft Graph **delegated scopes** the agent may request (allow-list)
- **App roles** for service-to-service calls (e.g., `Agent365.Observability.OtelWrite`)
- **Allowed MCP tool servers**
- **Compliance** and audit requirements
- Linked **governance policies** — DLP, external access, logging

When a blueprint is activated in a tenant, **users request instances** from their admin
via the M365 Admin Center. Every instance **inherits** the blueprint's rules — there is
no per-instance consent, no posture drift, no shadow agents.

| Governance benefit | How it lands |
|---|---|
| No shadow agents | Instances can only be created from approved blueprints |
| Consistent posture | Scopes, roles, tools, policies inherited on creation |
| Revocable from one place | Disable the blueprint → every instance is affected |
| Auditable by principal | Every action has an Entra identity attached |

**In this repo**

- Policy spec authored independently of Entra (the contract): [docs/blueprint-policy.md](blueprint-policy.md)
- Diagram + inheritance contract: [docs/design.md](design.md#a365-governance-plane)
- Multi-instance inheritance proof: [scripts/provision-second-instance.ps1](../scripts/provision-second-instance.ps1)

**Reference:** [Microsoft Entra agent blueprint](https://learn.microsoft.com/en-us/entra/agent-id/identity-platform/agent-blueprint)

### 2.3 Governed MCP Tool Servers (Work IQ)

A365 exposes Microsoft 365 and business workloads as **Model Context Protocol (MCP)
servers**. Your agent never talks to Graph directly; it invokes governed MCP endpoints
that enforce admin policy *at the tool boundary*. This family is marketed as **Work IQ**
and is continuously evaluated for accuracy, latency, and reliability.

| Server (preview) | Capabilities |
|---|---|
| Work IQ **Mail** | Create/update/delete messages, reply, semantic search |
| Work IQ **Calendar** | Create/list/update/delete events, accept/decline, conflict resolution |
| Work IQ **SharePoint** | Upload files, metadata, search, lists |
| Work IQ **OneDrive** | Personal OneDrive file and folder management |
| Work IQ **Teams** | Chat CRUD, members, messages, channel ops |
| Work IQ **Word** | Create/read docs, add and reply to comments |
| Work IQ **User** | Manager, direct reports, profile, user search |
| Work IQ **Copilot** | Chat with M365 Copilot, ground on files |
| Dataverse / Dynamics 365 | CRUD + domain actions |

**Governance properties** every MCP call flows through:

- **Admin control** — each MCP server is a permission on the Agent 365 application; admins allow/block per server in the M365 Admin Center.
- **Scoped access** — agents get only the permissions they need.
- **Observability** — every tool call is traced (see §2.4).
- **Policy enforcement** — runtime rate limits, payload checks, security scans.

**Custom MCP servers** are supported via the **MCP Management Server** (API-first), which
lets tenant admins compose scenario-focused servers from 1,500+ connectors, Graph APIs,
Dataverse custom APIs, or any REST endpoint.

**In this repo**

- Allow-list: [ToolingManifest.json](../ToolingManifest.json) pins `mcp_MailTools` + `mcp_CalendarTools`.
- Runtime registration: `setup_mcp_servers()` in [agent.py](../agent.py) uses `microsoft-agents-a365-tooling-extensions-openai`.

**Reference:** [Work IQ MCP overview](https://learn.microsoft.com/en-us/microsoft-agent-365/tooling-servers-overview)

### 2.4 Observability (OpenTelemetry + Defender)

A365 observability is plain **OpenTelemetry**, but with three governed additions:

1. **Structured spans** for *agent invocation*, *tool execution*, and *LLM inference* with consistent attributes across frameworks.
2. A pluggable **exporter** that ships to the A365 backend and surfaces in **Microsoft Defender Advanced Hunting** (admins can KQL-query trace logs, parameters, and outcomes).
3. An inheritable **S2S app role** — `Agent365.Observability.OtelWrite` — assigned to the blueprint SP so every instance inherits the ability to write traces.

Admins can run hunting queries to inspect tool calls, detect anomalies, and audit
agent activity — the same surface used for endpoint and identity threat hunting.

**In this repo**

- Configuration: `_setup_observability()` in [agent.py](../agent.py) calls `configure()` then `OpenAIAgentsTraceInstrumentor().instrument()`.
- Secure export token resolver: `token_resolver` in [agent.py](../agent.py), cache in [token_cache.py](../token_cache.py).
- Inheritable role assignment: [scripts/assign-observability-role.ps1](../scripts/assign-observability-role.ps1).

**References**

- [Agent 365 SDK observability](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/agent-365-sdk?tabs=python)
- [Monitor agents with Microsoft Defender](https://learn.microsoft.com/en-us/microsoft-agent-365/admin/threat-protection)
- [OpenTelemetry](https://opentelemetry.io/)

### 2.5 Authentication flows

A365 supports **two** authentication flows, both powered by Microsoft Entra Agent ID:

| Flow | What it is | Use when |
|---|---|---|
| **Agent identity (agentic auth, S2S)** | Agent acts as itself, using its own blueprint-derived credentials | Autonomous ops, scheduled tasks, sending from the agent's own mailbox, background work |
| **On-Behalf-Of (OBO)** | Agent exchanges a user's delegated token and acts with the user's permissions | Accessing user-specific data (inbox, calendar, files), actions that require user consent |

OBO provides stronger auditing in reactive flows because every action is tied back to a
real user principal.

#### Decision matrix — OBO / S2S / Both

The AI-guided onboarding asks **"OBO, S2S, or Both?"** as its second policy
question. The answer drives which federated credentials the blueprint carries
and which auth handlers the agent host registers. Use this matrix to pick:

| Mode | Pick when the agent is… | Repo wiring |
|---|---|---|
| **OBO only** | Always reacting to a user turn (Teams chat, Outlook reply, Word comment). Every action should attribute to *that user*, not the agent | `USE_AGENTIC_AUTH=false` + `AUTH_HANDLER_NAME=user` in [env/.env.playground](../env/.env.playground); `agent_app.auth.exchange_token(context, scopes=...)` in [host_agent_server.py](../host_agent_server.py) `on_message` |
| **S2S only** | Always running headless (cron, queue worker, scheduled report) with no human in the loop. Actions attribute to the agent identity itself | `USE_AGENTIC_AUTH=true` + `AUTH_HANDLER_NAME=agentic`; federated credential on the blueprint SP; observability ingest follows this path today |
| **Both** | Mixed: usually reactive (OBO) but occasionally needs to act on its own (S2S) — e.g. "reply to me, *and* file a follow-up reminder for tomorrow morning" | Both handlers registered; `USE_AGENTIC_AUTH` flips per call site; the host picks based on whether a user activity is in scope |

The **observability ingest** path always uses S2S (the role lives on the
blueprint SP — see [§3.3](#33-what-does-inheritance-actually-mean-mechanically)),
so even an "OBO only" agent is implicitly S2S for telemetry. Picking *Both* in
the AI-guided flow is the safe default if you're unsure; it costs nothing extra
and keeps room for future scenarios.

**In this repo**

- Both flows are wired; `USE_AGENTIC_AUTH` in [env/.env.playground](../env/.env.playground) toggles between them.
- Token exchange + caching happens in `GenericAgentHost.on_message` in [host_agent_server.py](../host_agent_server.py) via `agent_app.auth.exchange_token(...)`.
- Bearer-token dev mode is provided by [local_authentication_options.py](../local_authentication_options.py).

**Reference:** [Authentication flows](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/identity#authentication-flows)

### 2.6 Notifications and lifecycle

Agents are addressable the same way people are — `@mention` in Teams, reply in Outlook,
comment in Word. The notifications layer handles channel routing and lifecycle events:
install (`agentInstanceCreated`), uninstall, invoked.

**In this repo**

- `on_installation_update` in [host_agent_server.py](../host_agent_server.py) sends a welcome message on `add` and a farewell on `remove`.
- Playground: use **Mock an Activity → Install application** to replay the `installationUpdate` activity.

### 2.7 The Agent 365 CLI

The CLI is the command-line backbone for the full lifecycle:

- Create blueprints and supporting resources
- Manage MCP servers, permissions, and tooling
- Deploy agent code to Azure
- Publish agent application packages to the Admin Center
- Clean up blueprints, identities, and Azure resources

**In this repo**

- Driven by [scripts/setup-environment.ps1](../scripts/setup-environment.ps1) (`a365 config init`, `a365 setup all`) and [scripts/teardown-environment.ps1](../scripts/teardown-environment.ps1) for cleanup.
- Failure modes and workarounds: [TROUBLESHOOTING.md](../TROUBLESHOOTING.md).

**Reference:** [Agent 365 CLI](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/agent-365-cli)

---

## 3. Governance Deep-Dive: Blueprint + Inheritance

Governance is the most A365-specific pillar and the place where the platform earns
its keep. This section unpacks the blueprint — *what* it solves, *what* it contains,
and *how* inheritance actually works mechanically. Every other A365 capability hangs
off this concept, so it is worth absorbing slowly.

### 3.1 What problem does the blueprint solve?

Imagine an org with 50 agents, each built by a different team. Without a blueprint:

- Each team independently registers an Entra app, picks scopes, asks for admin
  consent.
- Each agent ends up with a **different** posture. Team A's calendar agent has
  `Mail.ReadWrite`; team B's identical-looking agent has `Mail.Send` only. **Drift.**
- An admin who wants to tighten policy (*"no agent in finance can read mailboxes"*)
  has to chase 50 separate app registrations.
- A new instance of the same agent (e.g. one per region) requires re-doing all of
  the consent.

The blueprint exists to make the **policy** the unit of governance, not the
**instance**. One blueprint = one declared posture. *N* instances inherit it. Admins
manage one thing, not *N*.

### 3.2 What is actually in a blueprint?

In Entra terms, the blueprint is an **agentic application** — a special flavour of
app registration. It carries:

| What | Where it shows up in this repo |
|---|---|
| Required Graph delegated scopes (`User.Read.All`, `Mail.Send`, etc.) | [a365.config.json](../a365.config.json) — consumed by `a365 setup all` |
| Required app roles on Microsoft resources (e.g. `Agent365.Observability.OtelWrite`) | [scripts/assign-observability-role.ps1](../scripts/assign-observability-role.ps1) |
| Allowed MCP tooling | [ToolingManifest.json](../ToolingManifest.json) — Mail + Calendar |
| Auth handler configuration (federated credential type, audience) | `.env` → `AGENTAPPLICATION__USERAUTHORIZATION__HANDLERS__AGENTIC__SETTINGS__TYPE=AgenticUserAuthorization` |
| Infrastructure template (optional) | `webAppName` field in the config |

*Concretely in this tenant:* blueprint app id `19bc459c-7807-4a41-a467-4adfb9f9704b`,
blueprint SP `306cc506-1f1d-4d46-b89d-22865aee933f`. The `OtelWrite` role is assigned
**once, on the blueprint SP** — and that is where every instance picks it up from.

### 3.3 What does inheritance actually mean, mechanically?

This is the part most people get wrong. Inheritance here is **not** *"the blueprint
runs and the instances ask it for permission at runtime."* It is two distinct
mechanisms working together:

#### Mechanism 1 — Provisioning-time projection (delegated scopes)

When `a365 create-instance identity` runs, the CLI:

1. Creates a new app registration (the **instance app**) and SP.
2. Creates an `agentUser` directory object (the agent's *"person"* identity).
3. **Copies** the blueprint's allow-list onto the instance SP as
   `oauth2PermissionGrants` (delegated scopes).

That is why our two instances showed *byte-identical* scope sets in the evidence
artifact — the CLI literally projected the same allow-list onto both instance SPs.

#### Mechanism 2 — Centralized S2S role on the blueprint SP

The CLI does **not** copy the S2S app-role assignments onto the instance SP. Those
stay on the blueprint SP. The instance acquires its observability token *as the
blueprint identity* via federated credential exchange.

That is why our `OtelWrite` role assignment lives only on `306cc506-...` and not on
either instance — see
[docs/evidence/multi-instance-inheritance.md](evidence/multi-instance-inheritance.md).

#### Why the split matters

| Mechanism | What inherits | Why centralize vs. project |
|---|---|---|
| Delegated scopes | Projected onto each instance SP | Each instance is a separate principal that users consent to individually — needs its own grants |
| S2S app roles | Assigned only on the blueprint SP | One identity acts as the system-to-system caller; centralization means revocation is atomic |

#### Mechanism 3 — Runtime token resolution

When the agent emits OTel spans, it asks the auth handler for an
observability-scoped token. That request is fulfilled by the blueprint SP's S2S
credential — which is where the role lives. So inheritance is not just naming; it
is a real auth flow.

#### Policy revocation is atomic

If you remove `OtelWrite` from the blueprint SP, **every** instance loses
observability access on its next token mint. There is no *"but this instance was
already granted it"* gap. That is the design choice that makes A365 governable at
scale.

### 3.4 Why the split (project vs. centralize) matters

The split — **delegated scopes copied onto each instance, S2S roles centralized on
the blueprint** — is what lets A365 give admins both:

- **Per-instance accountability** for user-facing actions (each instance shows up in
  consent UI as itself, audit logs attribute Mail/Calendar reads to the instance SP).
- **Single-point governance** for system-to-system actions (one role on one
  blueprint SP controls observability for the entire fleet).

A naive design would have put everything on the blueprint (no per-instance
accountability) or copied everything onto each instance (no central revocation).
A365 deliberately splits along the user-facing vs. system-to-system axis.

---

## 4. Security Deep-Dive: Agentic Identity + Governed Tooling

Governance answers *"who is allowed to do what?"* Security answers *"how does the
agent prove who it is, and how is it stopped from touching things outside its
lane?"* A365's answer comes in two halves: a new directory object type for the
identity, and Microsoft-hosted MCP servers for the data path.

### 4.1 Why "agentic identity" is the central trick

The single most important design decision A365 made: **an agent is not a service
principal — it is an `agentUser`.** That is a brand-new directory object type
Microsoft added to Entra specifically for A365.

Compare the three options side by side:

| Property | Traditional service principal | Service account (legacy) | **Agentic user** (A365) |
|---|---|---|---|
| Has a UPN / mailbox | No | Yes | **Yes** |
| Shows up in people picker / org chart | No | Yes (clutter) | **Yes (marked agentic)** |
| Can hold secrets / passwords | Yes | Yes | **No** |
| Can hold MFA factors | No | Yes | **No** |
| Can be governed by Conditional Access | Limited | Yes | **Yes** |
| DLP / Purview retention applies | No | Yes | **Yes** |
| Defender threat detection applies | Limited | Yes | **Yes** |
| Token shape | `idtyp=app` | `idtyp=user` | `idtyp=user` + agentic marker |
| Auth method | Client secret / cert / MI | Password (bad) | **Federated credential only** |

**The win:** every Microsoft 365 governance tool that already understands *"user"*
— Purview DLP, Defender for Cloud Apps, Conditional Access, audit logs, eDiscovery
— automatically applies to the agent. *Without anyone writing new policy.*

**The cost:** you cannot use traditional auth flows. The agent must authenticate
via federated credential (workload identity, GitHub OIDC, etc.). No more
`client_secret` shortcuts.

### 4.2 How an agentic user gets a token (the auth dance)

When the agent emits an OTel span or calls an MCP tool, here is what actually
happens (much of it inside the SDK):

```
┌────────────────────────────────────────────────────────────────┐
│  1. Real Teams turn arrives at /api/messages                    │
│     bearer token = delegated token for the calling user         │
│     audience = ea9ffc3e (Work IQ Tools — A365 platform aud)     │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
┌────────────────────────────────────────────────────────────────┐
│  2. host_agent_server.on_message receives turn                  │
│     reads context.activity.recipient.tenant_id +                │
│           context.activity.recipient.agentic_app_id             │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
┌────────────────────────────────────────────────────────────────┐
│  3. agent_app.auth.exchange_token(context, scopes=...)          │
│     OBO-style exchange: turns the user's delegated token into   │
│     an *agentic* token for this agent's identity.               │
│     Entra checks:                                               │
│       - is the agent registered as agentic? (yes)               │
│       - does the blueprint allow this scope? (yes, allow-list)  │
│       - is the user permitted to act through this agent? (yes)  │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
┌────────────────────────────────────────────────────────────────┐
│  4. Cached as agentic token, used for downstream calls:         │
│       - MCP servers (Mail/Calendar)                             │
│       - A365 observability ingest                               │
│     Tokens carry agent_id baggage so the backend can attribute  │
│     every span / Graph call to the right agent identity.        │
└────────────────────────────────────────────────────────────────┘
```

*In this repo:* the exchange happens in
[host_agent_server.py](../host_agent_server.py) `on_message` (≈ line 245) via
`agent_app.auth.exchange_token(...)`, and the resulting token is cached by
[token_cache.py](../token_cache.py) for the `token_resolver` in
[agent.py](../agent.py) to pick up.

**Key insight:** the agent never holds a long-lived credential of its own. It always
derives its current authority **from the user it is acting on behalf of**,
*constrained by the blueprint's allow-list*. Which means:

- If a user is offboarded → all their agents lose authority next turn.
- If the blueprint loses a scope → all agents lose that scope on next mint.
- There is no *"but the agent was already running"* gap.

This is the Entra-native answer to a problem that has historically required custom
code (token rotation, just-in-time access, etc.).

### 4.3 Governed tooling via MCP (the second half of security)

Identity is half of security. The other half is **what the agent is allowed to
touch**. A365's answer: **MCP servers run by Microsoft, audited by Microsoft.**

In this repo, [ToolingManifest.json](../ToolingManifest.json) registers two:

| MCP server | What it does | Why it matters |
|---|---|---|
| `mcp_MailTools` | Mail.Send, Mail.ReadWrite, etc. — exposed as a small set of *tools*, not raw Graph endpoints | Microsoft owns the MCP server, so it can throttle, log, redact, and DLP-scan before the call ever reaches Exchange |
| `mcp_CalendarTools` | Calendar read / write | Same model — Microsoft sits in the data path |

Why this matters for governance:

1. **The agent never holds raw `Mail.ReadWrite` against Graph.** It holds
   `McpServers.Mail.All` against Microsoft's MCP server, and the MCP server makes
   the Graph call after applying its own checks.
2. **Microsoft can enforce policy in one place.** Tenant-wide rules (e.g. *"no
   agent in this tenant may send external mail"*) are applied at the MCP server,
   not in 50 different agent codebases.
3. **Audit attribution is unambiguous.** The MCP server logs *agent → tool →
   tenant → user* on every call. The Graph audit log shows the MCP server as the
   caller; the MCP server's audit shows the agent.
4. **DLP / Defender hook into the MCP boundary.** Same place as the audit — one
   pane of glass.

If you want a custom tool (e.g. internal CRM), you can register your own MCP
server in the tooling manifest — but you take on the audit/policy responsibility
yourself for that tool, just as you would in any tenant-extension scenario.

---

## 5. Observability Deep-Dive: OpenTelemetry into the Tenant

Governance and security are guardrails. Observability is the proof those guardrails
are working — and the only pillar that turns invisible agent behavior into
measurable signal an admin can query.

### 5.1 Why OpenTelemetry, not a Microsoft-proprietary protocol

A365 picked **OpenTelemetry** as the wire format on purpose:

1. **Vendor-neutral.** Your agent already emits OTel spans for its own debugging
   (Application Insights, Honeycomb, Jaeger, etc.). A365 just adds *one more
   exporter* to the same span pipeline. Zero code rewrite.
2. **Standard semantic conventions.** OTel's GenAI semantic conventions
   (`gen_ai.system`, `gen_ai.request.model`, `gen_ai.usage.input_tokens`, etc.)
   are already understood by every observability vendor. A365 ingests the same
   spans an APM tool already understands.
3. **Microsoft can ingest into Defender Advanced Hunting and surface in Admin
   Center** without inventing a new SDK, because OTel → Kusto is an already-
   solved pipeline inside Microsoft.

The trade-off: the wire is generic, but the **routing decisions are A365-specific**
— which spans go to A365, which baggage they must carry, what the auth header
looks like. That is what the A365 exporter encapsulates.

### 5.2 What the exporter actually does (the wiring in this repo)

[agent.py](../agent.py) calls `configure(service_name, service_namespace,
token_resolver)`. Under the hood:

```
                              ┌─────────────────────────────┐
  OpenAI Agents SDK runs an   │  OpenAIAgentsTraceInstrumentor│
  inference                   │  (auto-emits OTel spans for   │
                              │   every agent + tool call)    │
                              └──────────────┬───────────────┘
                                             │ spans
                                             ▼
                              ┌─────────────────────────────┐
                              │  OTel SDK SpanProcessor       │
                              │  (batches, adds resource attrs│
                              │   for service_name/namespace) │
                              └──────────────┬───────────────┘
                                             │
                       ┌─────────────────────┴─────────────────────┐
                       ▼                                           ▼
              ┌───────────────────┐                  ┌──────────────────────┐
              │  Console exporter  │                  │  A365 exporter          │
              │  (dev-only)        │                  │  - calls token_resolver │
              │                    │                  │  - reads tenant_id +    │
              │                    │                  │    agent_id from        │
              │                    │                  │    BaggageBuilder ctx   │
              │                    │                  │  - POSTs OTLP to        │
              │                    │                  │    agent365.svc.cloud.. │
              └───────────────────┘                  └──────────────────────┘
```

The two pieces of repo work that make this real:

- **`token_resolver` in [agent.py](../agent.py)** — the exporter calls back into
  your code to mint the auth header. This repo implements two-tier resolution:
  cached agentic token from the turn (real auth path), falling back to
  `OBS_S2S_TOKEN` (Playground / local-dev path). That callback shape is *the*
  extension point A365 gives you.
- **`BaggageBuilder().tenant_id(...).agent_id(...).build()` in
  [host_agent_server.py](../host_agent_server.py)** — wraps the message handler in
  an OTel context that stamps every downstream span with the right tenant + agent
  ids. That is how the backend partitions multi-tenant data.

The A365 exporter source ships at
`microsoft_agents_a365/exporters/agent365_exporter.py` if you want to read what it
does byte-by-byte.

### 5.3 What the tenant gets in return

This is what lights up at the M365 Admin Center end (and is the part the 403 from
row [G9](project-scope.md) is currently blocking on this non-Frontier tenant):

| Tenant-side capability | What it gives admins |
|---|---|
| **Admin Center → Agents view** | Per-agent dashboards: invocation count, success rate, latency, token cost |
| **Defender Advanced Hunting** | KQL over agent telemetry: *"show every agent that called Mail.Send to an external recipient in the last 24 h"* |
| **Per-instance scorecard** | Same spans partitioned by `agent_id` baggage — instance 1 vs. instance 2 cleanly separated |
| **Cross-agent investigation** | `correlation_id` baggage links agent-to-agent calls into a single trace |

**What this repo proved end-to-end** (without the tenant gate open):

- Exporter is wired correctly (no console fallback in startup logs).
- Tokens are resolved correctly (no auth errors at the client side).
- Spans carry the right baggage (`tenant_id`, `agent_id` from `BaggageBuilder`).
- POSTs hit the real A365 ingest endpoint.
- Backend says 403 — *gated, not broken* (see
  [project-scope.md §15 → G9](project-scope.md)).

**When the tenant gate opens, the wiring does not change.** That is the entire
point of a reference starter — pre-build the client-side correctness, wait for the
platform.

---

## 6. How the Pieces Fit in This Starter

```
                         ┌──────────────────────────────┐
                         │  Microsoft Entra + A365      │   ← Governance plane
                         │  Blueprint (agentic app)  ───┼─► inherited by every instance
                         │    • scopes (allow-list)     │      (agentic app instance
                         │    • app roles (OtelWrite)   │       + agentic user)
                         │    • MCP allow-list          │
                         │    • compliance policy       │
                         └──────────────┬───────────────┘
                                        │ identity + policy
                                        ▼
  user message       ┌────────────────────────────────────┐        governed MCP calls
  ───────────────────▶│  GenericAgentHost (M365 Agents SDK)│──────▶  Work IQ Mail /
  (Teams/Playground) │    host_agent_server.py            │        Calendar
                     │                                    │        (ToolingManifest.json)
                     │  OpenAIAgentWithMCP                 │──────▶  Azure OpenAI
                     │    agent.py                         │        (LLM inference)
                     └────────────────────┬───────────────┘
                                          │ OpenTelemetry spans
                                          ▼
                                ┌──────────────────────────┐
                                │  A365 Observability +    │
                                │  Defender Advanced Hunt  │
                                └──────────────────────────┘
```

- **Runtime path** (left → right): user → host → LLM + MCP tools → response.
- **Governance path** (top-down): blueprint posture flows into every instance automatically.
- **Audit path** (bottom): every span is exported to A365 observability, visible in Defender.

The full diagram with the posture-inheritance table lives in [design.md](design.md#a365-governance-plane).

---

## 7. Concept-to-Code Map

Use this table when you want to jump from a concept in the official docs straight to
the line(s) in this repo that implement it.

| Concept | Docs | Code / Config |
|---|---|---|
| Agent identity (blueprint → instance → agentic user) | [Identity](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/identity) | [scripts/setup-environment.ps1](../scripts/setup-environment.ps1), `a365.config.json` |
| Caller identity per turn | [SDK overview](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/agent-365-sdk?tabs=python) | `on_message` in [host_agent_server.py](../host_agent_server.py) |
| Blueprint registration | [Entra agent blueprint](https://learn.microsoft.com/en-us/entra/agent-id/identity-platform/agent-blueprint) | `a365 setup all` in [scripts/setup-environment.ps1](../scripts/setup-environment.ps1) |
| Blueprint policy allow-list (this starter) | — | [docs/blueprint-policy.md](blueprint-policy.md) |
| Inheritable S2S role (OtelWrite) | [SDK overview](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/agent-365-sdk?tabs=python) | [scripts/assign-observability-role.ps1](../scripts/assign-observability-role.ps1) |
| Governed MCP allow-list | [Work IQ MCP](https://learn.microsoft.com/en-us/microsoft-agent-365/tooling-servers-overview) | [ToolingManifest.json](../ToolingManifest.json) |
| MCP registration at runtime | [Work IQ MCP](https://learn.microsoft.com/en-us/microsoft-agent-365/tooling-servers-overview) | `setup_mcp_servers` in [agent.py](../agent.py) |
| Observability `configure()` | [SDK overview](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/agent-365-sdk?tabs=python) | `_setup_observability` in [agent.py](../agent.py) |
| Secure trace export token resolver | [SDK overview](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/agent-365-sdk?tabs=python) | `token_resolver` in [agent.py](../agent.py), cache in [token_cache.py](../token_cache.py) |
| Install / uninstall lifecycle | [SDK overview](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/agent-365-sdk?tabs=python) | `on_installation_update` in [host_agent_server.py](../host_agent_server.py) |
| Agentic auth vs. OBO vs. bearer-token dev mode | [Authentication flows](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/identity#authentication-flows) | `USE_AGENTIC_AUTH` in [host_agent_server.py](../host_agent_server.py), [local_authentication_options.py](../local_authentication_options.py) |
| Multi-instance inheritance proof | — | [scripts/provision-second-instance.ps1](../scripts/provision-second-instance.ps1) |
| CLI-driven provisioning lifecycle | [Agent 365 CLI](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/agent-365-cli) | [scripts/setup-environment.ps1](../scripts/setup-environment.ps1), [scripts/teardown-environment.ps1](../scripts/teardown-environment.ps1) |

---

## 8. SDK Package Cheat Sheet (Python)

The starter pulls these from PyPI; each maps to a concept above.

| Package | Role in this starter |
|---|---|
| `microsoft-agents-hosting-aiohttp` / `-core` | M365 Agents SDK host — `CloudAdapter`, `AgentApplication`, `/api/messages` |
| `microsoft-agents-a365-tooling` | Core MCP tool-server management |
| `microsoft-agents-a365-tooling-extensions-openai` | Registers MCP servers with the OpenAI Agents SDK agent object |
| `microsoft-agents-a365-observability-core` | `configure()`, span definitions, exporter plumbing |
| `microsoft-agents-a365-observability-extensions-openai` | `OpenAIAgentsTraceInstrumentor` — auto-instruments OpenAI Agents SDK calls |
| `microsoft-agents-a365-runtime` | Power Platform API discovery, auth-scope resolution helpers |
| `microsoft-agents-a365-notifications` | Agent-addressable notifications + lifecycle events |
| `openai-agents` | The LLM orchestration framework this sample uses |

A365 also ships observability and tooling extensions for **Agent Framework**,
**Semantic Kernel**, **LangChain**, and **Azure AI Foundry** — pick the pair that
matches your framework and the rest of the SDK surface is identical.

**Reference:** [Agent 365 SDK packages](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/agent-365-sdk?tabs=python)

---

## 9. Mental Model — Why A365 Matters

Without a control plane, agents proliferate as isolated services:

- No shared identity → no audit trail
- No shared policy → security posture drifts
- No shared catalog → admins can't enforce, approve, or retire

A365 inverts this: **the blueprint is the contract**, every instance inherits it, and
the admin surfaces (M365 Admin Center, Entra, Defender, Purview) already understand it
because they already understand Entra principals. The pro-code agent's job reduces to
four things:

1. **Register** against a blueprint (via the CLI).
2. **Call** governed MCP servers instead of raw Graph.
3. **Emit** OTel spans via the provided instrumentor.
4. **Respect** the install / uninstall lifecycle.

Everything in this repo is a concrete example of those four jobs.

---

## 10. Recommended Reading Order

Newcomers: walk these in order, then come back to the concept-to-code map in §4.

1. [Product overview](https://www.microsoft.com/en-us/microsoft-agent-365) — 10-minute read; sets the *why*.
2. [Microsoft Agent 365 SDK and CLI](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/) — the layering diagram and how A365 differs from agent frameworks.
3. [Agent 365 SDK overview](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/agent-365-sdk?tabs=python) — the five capabilities in one page.
4. [Agent 365 Identity](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/identity) — blueprint → instance → agentic user; auth flows.
5. [Work IQ MCP overview](https://learn.microsoft.com/en-us/microsoft-agent-365/tooling-servers-overview) — governed tools, custom MCP servers, security model.
6. [Agent 365 Development Lifecycle](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/a365-dev-lifecycle) — how the SDK and CLI work together.
7. [Responsible AI for Agent 365](https://learn.microsoft.com/en-us/microsoft-agent-365/admin/responsible-ai-overview) — admin-facing policy surfaces.
8. This starter: [project-scope.md](project-scope.md) → [design.md](design.md) → [blueprint-policy.md](blueprint-policy.md) → [agent.py](../agent.py).

---

## 11. External References

### Agent 365 — product and developer docs

- [Microsoft Agent 365 — product overview](https://www.microsoft.com/en-us/microsoft-agent-365)
- [Microsoft Agent 365 SDK and CLI](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/)
- [Agent 365 SDK](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/agent-365-sdk?tabs=python)
- [Agent 365 CLI](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/agent-365-cli)
- [Agent 365 Development Lifecycle](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/a365-dev-lifecycle)
- [Agent 365 Identity](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/identity)
- [Agent registration](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/registration)
- [Configure agent testing](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/testing?tabs=python)

### Governance, security, and observability

- [Microsoft Entra agent blueprint](https://learn.microsoft.com/en-us/entra/agent-id/identity-platform/agent-blueprint)
- [Protect agent identities with Microsoft Entra](https://learn.microsoft.com/en-us/microsoft-agent-365/admin/capabilities-entra)
- [Monitor agents](https://learn.microsoft.com/en-us/microsoft-agent-365/admin/monitor-agents)
- [Monitor agents with Microsoft Defender](https://learn.microsoft.com/en-us/microsoft-agent-365/admin/threat-protection)
- [Responsible AI for Agent 365](https://learn.microsoft.com/en-us/microsoft-agent-365/admin/responsible-ai-overview)

### Tooling

- [Work IQ MCP overview](https://learn.microsoft.com/en-us/microsoft-agent-365/tooling-servers-overview)
- [Work IQ Mail reference](https://learn.microsoft.com/en-us/microsoft-agent-365/mcp-server-reference/mail)
- [Work IQ Calendar reference](https://learn.microsoft.com/en-us/microsoft-agent-365/mcp-server-reference/calendar)
- [Work IQ Teams reference](https://learn.microsoft.com/en-us/microsoft-agent-365/mcp-server-reference/teams)
- [Work IQ SharePoint reference](https://learn.microsoft.com/en-us/microsoft-agent-365/mcp-server-reference/sharepoint)
- [Work IQ OneDrive reference](https://learn.microsoft.com/en-us/microsoft-agent-365/mcp-server-reference/onedrive)
- [Work IQ Word reference](https://learn.microsoft.com/en-us/microsoft-agent-365/mcp-server-reference/word)
- [Work IQ User reference](https://learn.microsoft.com/en-us/microsoft-agent-365/mcp-server-reference/me)
- [Work IQ Copilot reference](https://learn.microsoft.com/en-us/microsoft-agent-365/mcp-server-reference/searchtools)
- [Dataverse / Dynamics 365 reference](https://learn.microsoft.com/en-us/microsoft-agent-365/mcp-server-reference/dataverse)
- [List of MCP servers certified by Microsoft](https://learn.microsoft.com/en-us/connectors/connector-reference/connector-reference-mcpserver-connectors)

### Adjacent platforms

- [Microsoft 365 Agents SDK](https://learn.microsoft.com/en-us/microsoft-365/agents-sdk/) (hosting layer underneath this sample)
- [Microsoft Copilot Studio](https://learn.microsoft.com/en-us/microsoft-copilot-studio/) (low-code path)
- [Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/what-is-foundry) (pro-code agent building on Azure)

### Standards and repos

- [OpenTelemetry](https://opentelemetry.io/)
- [Model Context Protocol](https://modelcontextprotocol.io/)
- [Microsoft Agent 365 Python SDK — GitHub](https://github.com/microsoft/Agent365-python)
- [Microsoft 365 Agents SDK — Python GitHub](https://github.com/Microsoft/Agents-for-python)
- [Frontier preview program](https://adoption.microsoft.com/copilot/frontier-program/)

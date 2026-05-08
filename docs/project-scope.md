# Project Scope & Expectations

> **Project:** A365 Governed Pro-Code Agent Starter
> **Type:** Capability & readiness exercise / reference starter (not a customer deliverable)
> **Audience:** Engineering, architecture, and delivery leads evaluating Microsoft Agent 365 (A365) for pro-code agent workloads

---

## TL;DR — Where this project stands today

If you only read one section, read this one.

- **GA status:** A365 went **General Availability on May 1, 2026**. The repo is post-GA;
  the only capability still gated by [Frontier](https://adoption.microsoft.com/copilot/frontier-program/) is the **AI teammate** tier (own UPN /
  mailbox / Teams presence). Register, Observability, and Work IQ tiers all run on any
  GA-licensed tenant.
- **What works end-to-end:** building the agent, provisioning Entra identity + Security Blueprint, multi-instance inheritance, OpenTelemetry exporter wiring, and a fully reproducible teardown → setup script round-trip. Local Playground is the verified runtime surface.
- **What's wired but Frontier-gated at runtime:** Teams 1:1 chat (G2), Admin Portal Agents view (G1), compliance-tab capture (G6), and OTel ingestion (G9) all ride on the AI teammate identity, so they need a Frontier-enrolled tenant — *not* a pre-GA wait.
- **Round-trip reproducibility:** `pwsh -File scripts/teardown-environment.ps1 -SkipConfirmation; pwsh -File scripts/setup-environment.ps1` will rebuild the entire environment with narrated step logs. The only manual touch-points are two WAM popups inside `a365 setup all` and an optional device-code login for the bearer token. Latest run: [docs/evidence/round-trip.md](evidence/round-trip.md).
- **How to read the rest:** Sections 1-9 are the framing (what this is, what success looks like, what's deliberately not in scope). Section 15 is the live status board — start there if you just want to know what's done vs. pending.

---

## 1. Project Intent

Build a **reference starter** that shows how a custom, pro-code agent plugs into **Microsoft Agent 365 (A365)** for enterprise governance.

This is a **vendor-reference exercise** — deliberately decoupled from any specific customer, industry, or business domain. The point is to establish patterns any team can fork the day A365 integration shows up on their roadmap.

---

## 2. Problem Statement

Enterprises adopting AI agents need a **governed, discoverable, and compliant** way to deploy them. Without a control plane:

- Agents proliferate as isolated services with no identity or audit trail.
- Security posture drifts between instances.
- Admins have no single surface to validate, approve, or retire agents.

Microsoft Agent 365 is positioned as the answer — but the integration story for **custom pro-code agents** (i.e., agents built outside Copilot Studio) isn't well documented in practice. This project closes that gap, end-to-end, with working code and reproducible scripts.

---

## 3. Goals

### 3.1 Primary Goals

1. Prove that a **pro-code agent** can be built, registered, and governed end-to-end using:
   - The **A365 Agent SDK**
   - The **M365 Agents SDK**
   - **Native Entra** identity primitives
2. Demonstrate the **A365 Security Blueprint** pattern — a centrally defined posture that all agent instances inherit automatically.
3. Produce **reusable automation** (scripts, configuration, documentation) that any team can fork as a starting point.

### 3.2 Secondary Goals

- Establish a baseline **troubleshooting catalogue** for common A365 integration failure modes.
- Produce a **governance-plane architecture reference** suitable for solution reviews.
- Validate the **observability pipeline** (OpenTelemetry → A365 backend) end-to-end.

### 3.3 Non-Goals

- Any customer-specific workload, UX, or branding.
- Copilot Studio parity, migration, or comparison.
- Production SLOs, disaster recovery, or multi-region topology.
- Custom MCP tool authoring beyond what is needed to exercise the platform (Mail + Calendar tools are sufficient).
- Fine-grained DLP, Purview labeling, or conditional access policy authoring.

---

## 4. In-Scope Capabilities

| # | Capability | Demonstrated Via |
|---|---|---|
| 1 | Pro-code agent built without Copilot Studio | OpenAI Agents SDK + `microsoft_agents_a365.*` packages |
| 2 | Enterprise hosting | M365 Agents SDK `CloudAdapter` + aiohttp |
| 3 | MCP tool integration | A365 Mail + Calendar MCP servers via `ToolingManifest.json` |
| 4 | Entra-backed agent identity (Entra ID, UPN, Teams presence) | `a365 setup all` provisioning |
| 5 | Security Blueprint creation and registration | Entra App registration with `AgentIdentityBlueprint.*` scopes |
| 6 | Automatic posture inheritance from blueprint to instances | Shared S2S roles + delegated grants |
| 7 | Observability (OpenTelemetry traces to A365) | `configure()` + `OpenAIAgentsTraceInstrumentor` |
| 8 | Agentic authentication (enterprise) and bearer-token mode (dev) | `USE_AGENTIC_AUTH` switch + token exchange |
| 9 | Multi-instance governance | Second instance bound to the same blueprint with zero per-instance config |
| 10 | Local verification harness | Microsoft 365 Agents Playground |
| 11 | Reproducible environment automation | End-to-end PowerShell setup script |

---

## 5. Out-of-Scope Capabilities

- Agents deployed as Teams message-extension apps, tabs, or connectors.
- Multi-tenant / partner-hosted agent scenarios.
- Agent-to-agent (A2A) orchestration.
- Custom model hosting beyond Azure OpenAI / OpenAI direct.
- Long-term data residency, tenancy, or regional failover analysis.
- Load, performance, or cost benchmarking.

---

## 6. Deliverables

| # | Deliverable | Form |
|---|---|---|
| D1 | Pro-code agent runtime | Source code (Python) |
| D2 | Security Blueprint policy specification | Markdown document |
| D3 | Automated environment setup | PowerShell script |
| D4 | Multi-instance inheritance proof | PowerShell script + generated evidence artifact |
| D5 | Governance-plane architecture reference | Markdown + diagram |
| D6 | Troubleshooting catalogue | Markdown document |
| D7 | Scope, expectations, asks, and gap analysis | This document (Section 15 Gap Analysis) |
| D8 | Executable verification steps | Script-based checklist |

---

## 7. Success Criteria

A run of the starter is considered successful when **all** of the following are true:

| # | Criterion | Verification Method |
|---|---|---|
| S1 | A pro-code agent responds to a user message without using Copilot Studio | Local Playground or deployed endpoint |
| S2 | The agent has a valid Entra identity, tenant-owned UPN, and mailbox | `az ad user show` |
| S3 | A Security Blueprint exists in Entra with the policy from `blueprint-policy.md` applied | Entra → Enterprise applications |
| S4 | Two instances of the agent exist under the same blueprint | `a365.generated.config.json` + evidence artifact |
| S5 | Both instances inherit the blueprint's delegated scopes and S2S roles with zero per-instance configuration | `Get-MgServicePrincipal*` verification |
| S6 | The agent is visible in the M365 Admin Portal agent directory | Screenshot |
| S7 | No A365 governance or compliance checks are flagged against the agent | Admin Portal compliance tab |
| S8 | OpenTelemetry traces are emitted successfully by both instances | Trace backend / exporter logs |
| S9 | A Teams 1:1 chat with the agent succeeds | Screen capture |
| S10 | The full environment can be re-provisioned on a clean tenant using only the scripts in `scripts/` | Dry-run on a second tenant / subscription |

---

## 8. Assumptions

- A **tenant with A365 GA features enabled** is available.
- An Azure subscription with permissions to create **Azure OpenAI** and **App Service** resources is available.
- The operator has:
  - **Global Administrator** or **Cloud Application Administrator** role in Entra (for admin consent).
  - **Owner** or **Contributor** on the target Azure subscription.
- The operator's workstation has **Windows + PowerShell 7+**, **Azure CLI**, **.NET 8+**, **Python 3.11+**, and **Git**.
- A **verified tenant domain** exists (the setup script resolves it automatically).

---

## 9. Constraints

| Constraint | Rationale |
|---|---|
| No Copilot Studio dependencies | Explicit project boundary — pro-code only |
| Must use the A365 Agent SDK | The starter is specifically about this SDK |
| Must run on a single tenant / single region | Scope control |
| LLM is Azure OpenAI (preferred) or OpenAI | Matches enterprise expectations, avoids custom model-hosting work |
| All automation is PowerShell / `az` / `a365` CLI | Matches the documented A365 tooling |
| No production data, no customer data | Reference implementation only |

---

## 10. Risks & Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| A365 CLI version drift breaks automation | Setup fails | Pin CLI version in setup script; document exact version in troubleshooting |
| WAM auth popups hidden behind VS Code | Blocks setup | Browser auth fallback documented and scripted |
| Azure OpenAI quota unavailable in chosen region | LLM calls fail | Script falls back to OpenAI direct mode |
| Tenant lacks A365 license | Blueprint creation fails | Verify license as a pre-flight check |
| Blueprint policy surfaces change across A365 releases | Policy doc drifts | Policy doc is the contract; re-verify against portal each release |
| Evidence artifacts (screenshots) age out as portals change | Documentation becomes stale | Store script-generated artifacts (Graph output, JSON) alongside screenshots |

---

## 11. Definition of Done

The starter is **Done** when all of these are true:

1. Every deliverable in Section 6 exists in the repository.
2. Every success criterion in Section 7 has verifiable evidence under `docs/evidence/`.
3. A clean-tenant re-provisioning run completes using only the repository scripts (see [docs/evidence/round-trip.md](evidence/round-trip.md) for the most recent reference run).
4. Section 15 Gap Analysis shows nothing left except **Done** or **Out of Scope**.
5. A short handover note (≤ 1 page) summarising the reusable patterns is added to the repository.

---

## 12. Roles (Generic)

| Role | Responsibility |
|---|---|
| **Tech Lead** | Owns scope, success criteria, and sign-off |
| **Agent Engineer** | Implements the pro-code agent, MCP integration, observability |
| **Platform / Identity Engineer** | Owns Entra app registration, blueprint policy, role assignments |
| **Verifier** | Executes success criteria on a clean tenant and captures evidence |

Roles are deliberately generic — any team adopting this starter can map them to its own staffing.

---

## 13. Reference Documents (Internal)

- [docs/learning-guide.md](learning-guide.md) — Concept-first A365 walkthrough with links to the official docs
- [docs/blueprint-policy.md](blueprint-policy.md) — Security Blueprint policy set
- [docs/design.md](design.md) — Runtime + governance-plane architecture
- [TROUBLESHOOTING.md](../TROUBLESHOOTING.md) — Known failure modes and resolutions
- [README.md](../README.md) — Repository entry point

---

## 14. Change Control

This scope is **fixed for the duration of a single starter run**. Any change — adding a tool, targeting a new hosting surface, introducing customer-specific logic — requires:

1. Explicit update to Section 4 (In-Scope) or Section 5 (Out-of-Scope).
2. Corresponding update to Section 7 (Success Criteria) if the change affects what "Done" means.
3. A matching entry in the gap analysis.

Without those updates, the new work is treated as **out of scope** and deferred to a follow-on iteration.

---

## 15. Gap Analysis — Current Status vs. Success Criteria

Snapshot of the repository against the success criteria in Section 7 and the original asks.

### 15.1 What Has Been Achieved

| # | Capability | Status | Evidence |
|---|---|---|---|
| 1 | Pro-code agent, no Copilot Studio | **Done** | [agent.py](../agent.py) uses OpenAI Agents SDK + `microsoft_agents_a365.*`; no Copilot Studio artifacts present |
| 2 | Hosting via M365 Agents SDK | **Done** | [host_agent_server.py](../host_agent_server.py) — `GenericAgentHost`, `CloudAdapter`, `AgentApplication`, aiohttp endpoint `/api/messages` |
| 3 | A365 SDK tooling integration (MCP) | **Done** | [ToolingManifest.json](../ToolingManifest.json) registers `mcp_MailTools` and `mcp_CalendarTools` |
| 4 | A365 Observability (tracing / monitoring) | **Done** | [agent.py](../agent.py) `_setup_observability()` wires `configure()` + `OpenAIAgentsTraceInstrumentor` with `token_resolver` |
| 5 | Entra client app with Blueprint permissions | **Done** | [scripts/setup-environment.ps1](../scripts/setup-environment.ps1) grants `AgentIdentityBlueprint.*`, `DelegatedPermissionGrant.ReadWrite.All`, etc. |
| 6 | Blueprint creation + registration in Entra | **Done (via CLI)** | `a365 setup all` invoked by setup script; `agentBlueprintId` emitted to `a365.generated.config.json` |
| 7 | Agent Identity (Entra + email + UPN) | **Done (via CLI)** | `a365.config.json` fields: `agentIdentityDisplayName`, `agentUserPrincipalName`, `agentUserDisplayName`, `managerEmail`, `agentUserUsageLocation` |
| 8 | Observability S2S inheritance (blueprint → role) | **Done** | [scripts/assign-observability-role.ps1](../scripts/assign-observability-role.ps1) assigns `Agent365.Observability.OtelWrite` to the blueprint SP |
| 9 | Agentic authentication path (enterprise mode) | **Done (wired)** | `USE_AGENTIC_AUTH` flag; token exchange in `GenericAgentHost.on_message` |
| 10 | Multi-message / typing indicator UX for Teams | **Done** | Pattern documented in [README.md](../README.md) and implemented in [host_agent_server.py](../host_agent_server.py) |
| 11 | Local verification harness | **Done** | [m365agents.playground.yml](../m365agents.playground.yml) + VS Code `Debug in Microsoft 365 Agents Playground` |
| 12 | Reproducible environment automation | **Done** | [scripts/setup-environment.ps1](../scripts/setup-environment.ps1) + [TROUBLESHOOTING.md](../TROUBLESHOOTING.md) |
| 13 | Security Blueprint policy specification | **Done** | [docs/blueprint-policy.md](blueprint-policy.md) |
| 14 | Governance-plane architecture reference | **Done** | [docs/design.md](design.md#a365-governance-plane) |

### 15.2 Gaps / Not Yet Demonstrated

All remaining gaps are **live-tenant execution + evidence capture** — scripts and documentation are in place; nothing has been run against a live A365 tenant yet.

| ID | Success Criterion | Status | Gap | Action |
|---|---|---|---|---|
| G1 | S6 — Admin Portal visibility | **Not verified** | No screenshot of the agent in M365 Admin Portal → Agents view | Sign in after `a365 setup all` and archive screenshot under `docs/evidence/` |
| G2 | S9 — Teams 1:1 chat | **Partial** | Only Playground exercised; no Teams-addressable chat verified | Deploy and install in Teams via the generated manifest; record a 1:1 chat |
| G3 | S10 — Clean-tenant deployment | **Scaffolded, not executed** | Setup script runs with `--skip-infrastructure`; App Service path not exercised end-to-end | Run `a365 setup all` without the skip flag, or add an `azd`/Bicep path |
| G4 | S3 — Blueprint policy applied | **Policy documented** | Policy authored in [blueprint-policy.md](blueprint-policy.md); runtime re-apply not verified | Run the re-apply steps in `blueprint-policy.md` against the live tenant |
| G5 | S4 — Two instances under one blueprint | **Done** | Instances `procodeagent` + `procodeagent2` provisioned under blueprint `19bc459c-...`; see [docs/evidence/multi-instance-inheritance.md](evidence/multi-instance-inheritance.md) | — |
| G6 | S7 — No compliance flags | **Not captured** | No screenshot/CLI output showing compliance status per instance | Capture `a365 compliance` / Admin Portal compliance tab per instance |
| G7 | S5 — Inheritance proof (policy/permissions) | **Done** | Graph-side verification shows byte-identical delegated scope sets on both instance SPs and a single `OtelWrite` role on the blueprint SP; see [docs/evidence/multi-instance-inheritance.md](evidence/multi-instance-inheritance.md) | — |
| G8 | S2 — Tenant-owned UPN + mailbox | **Code fix applied** | [scripts/setup-environment.ps1](../scripts/setup-environment.ps1) now resolves the default verified tenant domain via Graph | Re-run setup, then send a test mail and capture `az ad user show` |
| G9 | S8 — OTel traces from both instances | **Exporter validated, backend returns 403 on non-Frontier tenants** | Exporter is live and actively POSTing to `https://agent365.svc.cloud.microsoft/maven/agent365/agents/{agentId}/traces` with a resolved `OBS_S2S_TOKEN` and spans partitioned by tenant+agent id. Dev tenant rejects ingestion with HTTP 403 (correlation id `2b5c35d3-ea84-4485-ba0b-9606c91010b7`). Investigated `USE_AGENTIC_AUTH=true` as a cheaper alternative — ruled out because the agentic token-exchange path requires a real Teams turn carrying an OBO-eligible delegated user token; Playground bearer tokens are scoped to Work IQ Tools and cannot be re-exchanged for an agentic-identity token. Confirmed post-GA: AI-teammate-tier observability ingest remains Frontier-gated at General Availability — not a pre-GA wait. | Retest on a [Frontier-enrolled](https://adoption.microsoft.com/copilot/frontier-program/) tenant. The `USE_AGENTIC_AUTH=true` retest still applies but only after Teams installation lights up (G2). |
| G10 | Reproducible teardown → setup round-trip | **Done** | Hardened teardown (sync RG delete + Cognitive Services purge) and setup (Steps 7-10 closed: agent identity, OtelWrite roles, OBS_S2S_TOKEN, exporter flag) executed end-to-end with full Write-Stage narration. See [docs/evidence/round-trip.md](evidence/round-trip.md) for identifiers, step outcomes, and remaining manual touch-points (two WAM popups in `a365 setup all`; Step 11 device-code optional). | — |

### 15.3 Suggested Closure Order

What's left to do, in the order that makes the most sense (cheapest first, externally-blocked last):

1. **G8** — re-run setup so the generated identity uses the tenant-owned UPN; send a test mail and capture `az ad user show`.
2. **G1 + G6** — capture Admin Portal + compliance-tab screenshots. (~10 minutes once the tenant is in front of you.)
3. **G4** — apply the blueprint policy from [blueprint-policy.md](blueprint-policy.md) against the live tenant and confirm it sticks.
4. **G3 + G2** — deploy to App Service, install in Teams, record a working 1:1 chat. This unblocks the agentic-auth retest path inside G9.
5. **G9** — once on a [Frontier-enrolled](https://adoption.microsoft.com/copilot/frontier-program/) tenant, confirm OTel traces ingest cleanly from both instances; archive the trace IDs. (AI-teammate-tier ingest is Frontier-gated at GA, so a vanilla GA tenant will still see HTTP 403 here.)

**Already complete:** G5 (two instances) and G7 (inheritance proof) — see [docs/evidence/multi-instance-inheritance.md](evidence/multi-instance-inheritance.md). G10 (round-trip) — see [docs/evidence/round-trip.md](evidence/round-trip.md).

All artifacts for gap closure belong under `docs/evidence/` (folder already exists).

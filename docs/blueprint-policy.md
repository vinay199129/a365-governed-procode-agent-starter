# Security Blueprint Policy

Explicit policy set applied to the A365 Security Blueprint used by the
**A365 Governed Pro-Code Agent Starter**.
Blueprints are the Entra-registered governance anchor; every agent instance registered
against the blueprint inherits this posture automatically (no per-instance config).

## Identity & Registration

| Field | Value | Source |
|---|---|---|
| Blueprint display name | `<AgentName> Blueprint` | `a365.config.json` → `agentBlueprintDisplayName` |
| Blueprint App ID | generated | `a365.generated.config.json` → `agentBlueprintId` |
| Agent Identity display name | `<AgentName> Identity` | `a365.config.json` → `agentIdentityDisplayName` |
| Agent UPN | `<AgentName>@<verified-tenant-domain>` | Resolved dynamically (G10 fix) |
| Usage location | `US` | `a365.config.json` → `agentUserUsageLocation` |

## Inherited Delegated Scopes (Blueprint → Instance)

The blueprint SP grants these scopes (all `consentType=AllPrincipals`); every instance SP inherits the same set byte-for-byte at provisioning time. Verified empirically against two instances — see [docs/evidence/multi-instance-inheritance.md](evidence/multi-instance-inheritance.md).

| Resource | Scopes |
|---|---|
| Microsoft Graph | `User.Read.All`, `Mail.Send`, `Mail.ReadWrite`, `Chat.Read`, `Chat.ReadWrite`, `Files.Read.All`, `Sites.Read.All`, `ChannelMessage.Read.All`, `ChannelMessage.Send`, `Files.ReadWrite.All` |
| Work IQ Tools | `McpServers.Mail.All`, `McpServersMetadata.Read.All`, `McpServers.Calendar.All`, `McpServers.SharePoint.All`, `McpServers.Teams.All` |
| Messaging Bot API Application | `Authorization.ReadWrite`, `user_impersonation` |
| Agent365Observability | `user_impersonation`, `Agent365.Observability.OtelWrite` |
| Power Platform API | `Connectivity.Connections.Read` |

> The list above is the **allow-list**. Anything outside it must be added to the blueprint *and* re-consented — instances cannot elevate.

## Inherited App Roles (S2S)

| Resource App | Role Value | Role ID | Purpose |
|---|---|---|---|
| `Agent365 Observability` (`9b975845-388f-4429-889e-eab1ef63949c`) | `Agent365.Observability.OtelWrite` | `8f71190c-00c8-461d-a63b-f74abde9ba52` | Emit traces to A365 backend; assigned by [scripts/assign-observability-role.ps1](../scripts/assign-observability-role.ps1) |

**For local-dev only:** the same `OtelWrite` role is also assigned to the **client app SP** by `setup-environment.ps1` (Step 9). This is required because blueprint apps reject the client-credentials grant (`AADSTS82001`); the local-dev token mint in [scripts/refresh-observability-token.ps1](../scripts/refresh-observability-token.ps1) uses the client-app identity instead and needs the same role. Production runtime uses the blueprint SP via federated credential exchange and does not need the client-side role.

## Allowed Tools (MCP)

Defined in [ToolingManifest.json](../ToolingManifest.json). The manifest is the tool
allow-list; instances cannot call MCP servers not listed here.

| Tool | URL | Scope |
|---|---|---|
| `mcp_MailTools` | `https://agent365.svc.cloud.microsoft/agents/servers/mcp_MailTools` | `McpServers.Mail.All` |
| `mcp_CalendarTools` | `https://agent365.svc.cloud.microsoft/agents/servers/mcp_CalendarTools` | `McpServers.Calendar.All` |
| `mcp_SharePointTools` | `https://agent365.svc.cloud.microsoft/agents/servers/mcp_SharePointTools` | `McpServers.SharePoint.All` |
| `mcp_TeamsTools` | `https://agent365.svc.cloud.microsoft/agents/servers/mcp_TeamsTools` | `McpServers.Teams.All` |

## Data & Network Boundaries

- **LLM**: Azure OpenAI only (tenant-owned resource). No direct OpenAI-public endpoint from production.
- **Outbound**: Restricted to `*.microsoft.com`, `*.cloud.microsoft`, and the configured Azure OpenAI endpoint.
- **PII / content safety**: Azure OpenAI content filter defaults = `Medium` (Hate, Sexual, Violence, Self-harm).
- **Secrets**: No user secrets stored by the agent. Bearer tokens are short-lived and cached only in memory (see [token_cache.py](../token_cache.py)).

## Prompt-Injection Controls

Enforced in the system instructions in [agent.py](../agent.py):

- User input is treated as untrusted content, never as instructions.
- Agent never executes shell/system commands embedded in user messages.
- Tool calls only through registered MCP servers.

## Instance Governance

| Rule | Value | Enforced By |
|---|---|---|
| Max instances per user | `1` | A365 admin policy (to be set in M365 Admin Portal) |
| Install approval | Admin-consented via [scripts/setup-environment.ps1](../scripts/setup-environment.ps1) `admin-consent` step | Entra |
| Telemetry | Mandatory for every instance | Blueprint-inherited `OtelWrite` role |
| Uninstall behavior | Farewell message on `InstallationUpdate` `remove` | [host_agent_server.py](../host_agent_server.py) `on_installation_update` |

## Applying / Re-applying the Policy

1. Edit this file to change any entry above.
2. Update [ToolingManifest.json](../ToolingManifest.json) if the tool allow-list changed.
3. Re-run blueprint sync:
   ```powershell
   a365 setup all --skip-infrastructure --skip-requirements
   pwsh -NoProfile -File scripts/assign-observability-role.ps1
   ```
4. Re-verify in **Entra → Enterprise applications → `<AgentName> Blueprint` → Permissions** that the scope/role set matches this document.

## Verification Checklist

- [ ] Blueprint SP exists with App ID in `a365.generated.config.json`.
- [ ] Delegated scopes above are admin-consented on the blueprint.
- [ ] `Agent365.Observability.OtelWrite` is assigned to the blueprint SP.
- [ ] A second instance (see [scripts/provision-second-instance.ps1](../scripts/provision-second-instance.ps1)) passes all checks with zero additional config.
- [ ] M365 Admin Portal shows the agent with no compliance flags.

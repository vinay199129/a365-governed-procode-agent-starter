# Multi-Instance Inheritance Evidence

> Closes success criteria **S4** and **S5** in
> [docs/project-scope.md](../project-scope.md).

**Generated**: 2026-05-08 12:32:46Z
**Tenant**: `<tenant-id>`

> Tenant-specific identifiers (tenant id, app/SP/user GUIDs, UPNs) have been replaced with placeholders. Your values will differ on every run; the *shape* of the evidence is what matters.

## Shared blueprint

| Field | Value |
|---|---|
| Display name | `procodeagent Blueprint` |
| App ID | `<blueprint-app-id>` |
| Service principal object ID | `<blueprint-sp-id>` |

## Two instances under the blueprint

| # | Identity display name | Identity appId | Agent user UPN | Agent user object ID |
|---|---|---|---|---|
| 1 | procodeagent Identity | `<instance1-sp-id>` | `procodeagent@<your-tenant-domain>` | `<instance1-user-oid>` |
| 2 | procodeagent2 Identity | `<instance2-sp-id>` | `procodeagent2@<your-tenant-domain>` | `<instance2-user-oid>` |

Both were provisioned with `a365 create-instance identity` and the same
blueprint — **no per-instance scope list, no per-instance consent, no
per-instance role assignment**.

## Inheritance proof 1 — delegated scopes are identical on both instance SPs

| Resource | Scopes (consentType=AllPrincipals) |
|---|---|
| Microsoft Graph | `User.Read.All Mail.Send Mail.ReadWrite Chat.Read Chat.ReadWrite Files.Read.All Sites.Read.All ChannelMessage.Read.All ChannelMessage.Send Files.ReadWrite.All` |
| Work IQ Tools | `McpServers.Mail.All McpServersMetadata.Read.All McpServers.Calendar.All McpServers.SharePoint.All McpServers.Teams.All` |
| Messaging Bot API Application | `Authorization.ReadWrite user_impersonation` |
| Agent365Observability | `user_impersonation Agent365.Observability.OtelWrite` |
| Power Platform API | `Connectivity.Connections.Read` |

Signature check: scope set on instance 1 SP equals scope set on instance 2 SP
byte-for-byte.

## Inheritance proof 2 — S2S observability role lives on the blueprint SP only

`Agent365.Observability.OtelWrite` (`8f71190c-00c8-461d-a63b-f74abde9ba52`) is assigned once, on the
blueprint SP (`<blueprint-sp-id>`). Neither instance SP has its own copy. Any
additional instance created under this blueprint will inherit this role without
another role assignment step.

## Reproduction commands

```powershell
# Both users
az rest --method GET --uri "https://graph.microsoft.com/v1.0/users?$filter=startswith(userPrincipalName,'procodeagent')"

# Per-instance delegated grants
az rest --method GET --uri "https://graph.microsoft.com/v1.0/servicePrincipals/<instance-sp-id>/oauth2PermissionGrants"

# Blueprint S2S role assignments
az rest --method GET --uri "https://graph.microsoft.com/v1.0/servicePrincipals/<blueprint-sp-id>/appRoleAssignments"
```

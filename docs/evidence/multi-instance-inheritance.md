# Multi-Instance Inheritance Evidence

> Closes success criteria **S4** and **S5** in
> [docs/project-scope.md](../project-scope.md).

**Generated**: 2026-04-17 13:24:32Z
**Tenant**: `253bc031-a17c-4b57-b83c-1ee1d86b1331`

## Shared blueprint

| Field | Value |
|---|---|
| Display name | `procodeagent Blueprint` |
| App ID | `19bc459c-7807-4a41-a467-4adfb9f9704b` |
| Service principal object ID | `306cc506-1f1d-4d46-b89d-22865aee933f` |

## Two instances under the blueprint

| # | Identity display name | Identity appId | Agent user UPN | Agent user object ID |
|---|---|---|---|---|
| 1 | procodeagent Identity | 3aff3ab3-1a4d-4ea9-8400-0c45631c0f86 | procodeagent@vinay199129gmail.onmicrosoft.com | d4ad9d38-ba5a-41c5-a975-2511e9aeb0e4 |
| 2 | procodeagent2 Identity | adb53379-a440-48dd-9233-38f420d55811 | procodeagent2@vinay199129gmail.onmicrosoft.com | 42a9b043-daba-4cec-9348-b80ae8a4a35c |

Both were provisioned with `a365 create-instance identity` and the same
blueprint — **no per-instance scope list, no per-instance consent, no
per-instance role assignment**.

## Inheritance proof 1 — delegated scopes are identical on both instance SPs

| Resource | Scopes (consentType=AllPrincipals) |
|---|---|
| Microsoft Graph | `User.Read.All Mail.Send Mail.ReadWrite Chat.Read Chat.ReadWrite Files.Read.All Sites.Read.All ChannelMessage.Read.All ChannelMessage.Send Files.ReadWrite.All` |
| Work IQ Tools | `McpServers.Mail.All McpServersMetadata.Read.All McpServers.Calendar.All` |
| Messaging Bot API Application | `Authorization.ReadWrite user_impersonation` |
| Agent365Observability | `user_impersonation Agent365.Observability.OtelWrite` |
| Power Platform API | `Connectivity.Connections.Read` |

Signature check: scope set on instance 1 SP equals scope set on instance 2 SP
byte-for-byte.

## Inheritance proof 2 — S2S observability role lives on the blueprint SP only

`Agent365.Observability.OtelWrite` (`8f71190c-00c8-461d-a63b-f74abde9ba52`) is assigned once, on the
blueprint SP (`306cc506-1f1d-4d46-b89d-22865aee933f`). Neither instance SP has its own copy. Any
additional instance created under this blueprint will inherit this role without
another role assignment step.

## Reproduction commands

```powershell
# Both users
az rest --method GET --uri "https://graph.microsoft.com/v1.0/users?$filter=startswith(userPrincipalName,'procodeagent')"

# Per-instance delegated grants
az rest --method GET --uri "https://graph.microsoft.com/v1.0/servicePrincipals/<instance-sp-id>/oauth2PermissionGrants"

# Blueprint S2S role assignments
az rest --method GET --uri "https://graph.microsoft.com/v1.0/servicePrincipals/306cc506-1f1d-4d46-b89d-22865aee933f/appRoleAssignments"
```

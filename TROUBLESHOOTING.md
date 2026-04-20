# A365 Governed Pro-Code Agent Starter — Troubleshooting Guide

This guide documents every issue encountered during setup of the A365 Governed Pro-Code Agent Starter, with root cause analysis and verified resolutions. Use this as a reference when provisioning a fresh environment.

## Prerequisites Issues

### PowerShell 7+ Not Installed

**Symptom:** `a365 setup all` fails with `[FAIL] PowerShell Modules — PowerShell is not available on this system`.

**Root cause:** VS Code's default terminal uses Windows PowerShell 5.1 (`powershell.exe`). The A365 CLI requires PowerShell 7+ (`pwsh.exe`) for its Microsoft.Graph module operations.

**Resolution:**

```powershell
winget install --id Microsoft.PowerShell --source winget --accept-package-agreements --accept-source-agreements
```

After installing, refresh your terminal's PATH:

```powershell
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
pwsh --version  # Should show 7.x
```

### Azure CLI Login Not Persisting Across Terminals

**Symptom:** `az login` completes in one terminal but `az account show` returns "Please run az login" in other terminals.

**Root cause:** An interrupted `az login` (Ctrl+C, batch job conflict, or terminal crash) can fail to write tokens to disk. Subsequent terminals don't see credentials.

**Resolution:** Kill all stuck `az` processes, then run `az login` in a clean terminal:

```powershell
Get-Process az -ErrorAction SilentlyContinue | Stop-Process -Force
az login
```

If browser-based login consistently fails to persist, use device code flow:

```powershell
az login --use-device-code
```

## Entra App Registration Issues

### Missing Delegated Permissions

**Symptom:** `a365 config init` validation fails silently, or `a365 setup all` fails during blueprint creation.

**Root cause:** The CLI requires **7** delegated permissions (not 6 as some docs versions list):

| Permission | Purpose |
|---|---|
| `Application.ReadWrite.All` | Create/manage blueprint app registrations |
| `AgentIdentityBlueprint.ReadWrite.All` | Create and configure agent blueprints |
| `AgentIdentityBlueprint.UpdateAuthProperties.All` | Set inheritable permissions on blueprints |
| `AgentIdentityBlueprint.AddRemoveCreds.All` | Manage blueprint client secrets and credentials |
| `DelegatedPermissionGrant.ReadWrite.All` | Grant OAuth2 consent for agent instances |
| `Directory.Read.All` | Read directory data for validation |
| `User.ReadWrite.All` | Create agent users, set usage location, assign licenses |

**Resolution:** Always follow what the CLI outputs during `a365 config init`, not the docs. Add any missing permissions:

```powershell
$clientAppId = "<your-client-app-id>"
$graphId = "00000003-0000-0000-c000-000000000000"
$graphSp = az ad sp show --id $graphId --output json | ConvertFrom-Json

# Look up the permission ID
$perm = $graphSp.oauth2PermissionScopes | Where-Object { $_.value -eq "AgentIdentityBlueprint.AddRemoveCreds.All" }

# Add it
az ad app permission add --id $clientAppId --api $graphId --api-permissions "$($perm.id)=Scope"

# Re-grant admin consent
az ad app permission admin-consent --id $clientAppId
```

### `az ad app permission add` Fails with "Please provide both permission id and type"

**Symptom:** `az ad app permission add --api-permissions $permString` fails even though individual IDs are correct.

**Root cause:** When permission IDs are joined into a single PowerShell string variable (`$perms -join " "`), the `az` CLI receives them as one argument instead of separate positional arguments.

**Resolution:** Pass permissions as separate literal arguments, not via a joined string:

```powershell
# WRONG — single string variable
$permString = "id1=Scope id2=Scope"
az ad app permission add --id $appId --api $graphId --api-permissions $permString

# CORRECT — separate arguments
az ad app permission add --id $appId --api $graphId --api-permissions id1=Scope id2=Scope id3=Scope
```

## A365 CLI Configuration Issues

### Agent Name Validation Loop

**Symptom:** `a365 config init` rejects agent names with `ERROR: Agent name must start with a letter and contain only letters and numbers`.

**Root cause:** The CLI enforces strict naming for cross-platform compatibility: `^[a-zA-Z][a-zA-Z0-9]*$`. No hyphens, underscores, dots, or names starting with digits.

**Rejected examples:** `a365-poc`, `my_agent`, `001agentpoc`, `agent.mail`

**Accepted examples:** `procodeagent`, `myAgent42`, `AgentMail`

**Resolution:** Use a simple alphanumeric name starting with a letter.

### Deployment Path Accepts Wrong Default When Sending Whitespace

**Symptom:** Attempting to accept the default deployment path by sending a space character causes the CLI to receive a previous input value and reject it as a non-existent directory.

**Root cause:** Terminal input buffering can concatenate whitespace with previous prompt text.

**Resolution:** When accepting defaults in interactive CLI prompts via automation, send a completely empty string (just Enter) rather than whitespace.

## WAM (Windows Account Manager) Authentication Issues

### WAM Popup Hidden Behind VS Code

**Symptom:** The A365 CLI or `Connect-MgGraph` shows "Authenticating via Windows Account Manager..." and hangs indefinitely. No visible popup appears.

**Root cause:** WAM opens a native Windows sign-in dialog that renders behind VS Code's window in embedded terminals. The popup has no taskbar presence on some Windows versions and doesn't steal focus.

**Affected commands:**
- `a365 config init` (client app validation step)
- `a365 setup all` (S2S app role assignments step)
- `a365 setup admin` (S2S app role assignments step)
- `Connect-MgGraph` (default auth method)

**Resolution — Option A (find the popup):** Try Alt+Tab, check the taskbar for a "Sign in" icon, or check the system tray.

**Resolution — Option B (bypass WAM entirely):** For Microsoft Graph PowerShell SDK operations, disable WAM and use your custom client app ID to force browser auth:

```powershell
Set-MgGraphOption -DisableLoginByWAM $true
Connect-MgGraph -Scopes "AppRoleAssignment.ReadWrite.All" `
    -TenantId "<tenant-id>" `
    -ClientId "<your-custom-client-app-id>"
```

This opens a real browser tab that's always visible. See `scripts/assign-observability-role.ps1` for a working example.

**Resolution — Option C (device code flow):** For environments where no browser can open (remote, SSH):

```powershell
Connect-MgGraph -Scopes "AppRoleAssignment.ReadWrite.All" `
    -TenantId "<tenant-id>" `
    -UseDeviceCode
```

Note: Device code flow may fail for subsequent API calls due to token caching issues with WAM-enabled sessions. Option B is the most reliable.

### `a365 setup all` Completes with S2S Warning

**Symptom:** `a365 setup all` outputs "Warnings: S2S app role assignment failed for Observability API" but overall setup succeeds.

**Root cause:** The S2S step uses WAM auth which times out or is cancelled when the popup is hidden (Issue above).

**Impact:** Only affects production observability trace export to the A365 backend and Microsoft Defender. Local development with console traces works fine.

**Resolution:** After `a365 setup all` completes, run the observability role script separately:

```powershell
pwsh -NoProfile -File scripts/assign-observability-role.ps1
```

This script:
1. Reads blueprint and tenant IDs from `a365.config.json` and `a365.generated.config.json`
2. Disables WAM
3. Uses browser auth with the custom client app
4. Assigns the `Agent365.Observability.OtelWrite` app role to the blueprint service principal

## PowerShell Escaping Issues

### Nested `pwsh -Command` with `-Filter` Parameters

**Symptom:** Running `pwsh -Command "Get-MgServicePrincipal -Filter \"appId eq '...'\" "` from Windows PowerShell 5.1 fails with `A positional parameter cannot be found that accepts argument 'eq'`.

**Root cause:** Windows PowerShell 5.1 and PowerShell 7 handle quote escaping differently. When PS 5.1 shells into `pwsh -Command`, the `-Filter` string's embedded quotes get mangled across the shell boundary.

**Resolution:** Write commands to a `.ps1` script file and run with `pwsh -NoProfile -File script.ps1`. Script files are parsed by a single PowerShell engine, avoiding nested escaping:

```powershell
# WRONG — escaping nightmare
pwsh -Command "$bp = Get-MgServicePrincipal -Filter `"appId eq 'd8d86c53...'`""

# CORRECT — use a script file
# In assign-role.ps1:
$bp = Get-MgServicePrincipal -Filter "appId eq '$BlueprintAppId'"

# Run it:
pwsh -NoProfile -File assign-role.ps1
```

## Azure OpenAI Issues

### No LLM Model Available

**Symptom:** Agent `.env` has empty `OPENAI_API_KEY` and `AZURE_OPENAI_ENDPOINT`. Agent can't process messages.

**Root cause:** No Azure OpenAI resource or model deployment was provisioned. The sample assumes you bring your own credentials.

**Resolution:** Provision Azure OpenAI via CLI:

```powershell
# Create the resource (S0 SKU, requires OpenAI access approval on your subscription)
az cognitiveservices account create `
    --name <name>-openai `
    --resource-group <rg-name> `
    --location eastus `
    --kind OpenAI `
    --sku S0

# Deploy gpt-4o-mini
az cognitiveservices account deployment create `
    --name <name>-openai `
    --resource-group <rg-name> `
    --deployment-name gpt-4o-mini `
    --model-name gpt-4o-mini `
    --model-version "2024-07-18" `
    --model-format OpenAI `
    --sku-capacity 10 `
    --sku-name "GlobalStandard"

# Get endpoint and key for .env
az cognitiveservices account show --name <name>-openai --resource-group <rg-name> --query properties.endpoint -o tsv
az cognitiveservices account keys list --name <name>-openai --resource-group <rg-name> --query key1 -o tsv
```

If `GlobalStandard` SKU fails (quota), try `Standard`. If `az cognitiveservices account create` fails with access denied, you may need to [request Azure OpenAI access](https://aka.ms/oai/access) for your subscription.

The `scripts/setup-environment.ps1` script automates this entire provisioning.

## Local Testing Issues

### Bot Framework 404 When Sending Raw HTTP Messages

**Symptom:** Sending a POST to `http://localhost:3979/api/messages` with a Bot Framework Activity JSON causes `ClientResponseError: 404 Not Found` at `/v3/conversations/{id}/activities`.

**Root cause:** This is not a bug. The Bot Framework protocol requires a channel connector at the `serviceUrl` to receive agent replies. When you send a raw HTTP request, there's no connector listening, so the agent processes the message but fails when trying to deliver its response back.

**What works correctly:** The agent receives the message, calls Azure OpenAI, invokes MCP tools, and emits OpenTelemetry traces. Only the reply delivery fails because there's no channel.

**Resolution:** Use one of these proper test clients:

| Method | How |
|---|---|
| **Agents Playground** (recommended) | Install M365 Agents Toolkit extension, press F5 in VS Code |
| **Health endpoint** | `GET http://localhost:3979/api/health` — verifies agent is running and initialized |
| **Dev Tunnels + Teams** | Expose local port via Dev Tunnels, set as messaging endpoint, test in Teams |

## Round-Trip / Re-Provisioning Issues

These are the failure modes discovered while running `teardown-environment.ps1` → `setup-environment.ps1` end-to-end. All have been folded into the scripts; this section documents the *why* so future maintainers don't re-introduce them. Reference run: [docs/evidence/round-trip.md](docs/evidence/round-trip.md).

### Cognitive Services soft-delete blocks recreate-by-name

**Symptom:** Re-running `setup-environment.ps1` after a teardown fails on the Azure OpenAI step with `FlagMustBeSetForRestore` or `Account already exists in soft-deleted state`.

**Root cause:** `az group delete` removes the resource group, but Cognitive Services accounts go to a **48-hour soft-deleted shell** in the same region. The account name is reserved for that window; the next `az cognitiveservices account create` collides with the shell.

**Resolution (now scripted):** `teardown-environment.ps1` does the right thing — it captures every Cognitive Services account in the RG **before** delete, then runs `az group delete --yes` (synchronous, no `--no-wait`), then loops `az cognitiveservices account purge --name <acct> --resource-group <rg> --location <loc>` for each captured account *and* any soft-deleted account in the location whose name starts with the agent base name.

Manual fallback if you have to recover after a half-finished teardown:

```powershell
# Find soft-deleted accounts
az cognitiveservices account list-deleted --query "[?starts_with(name, 'procodeagent')]" -o table

# Purge them
az cognitiveservices account purge --name <name> --resource-group <rg> --location eastus
```

### `a365 setup all` hangs on "Configuring S2S app role assignments…"

**Symptom:** During `a365 setup all`, output stalls at `Configuring S2S app role assignments... / Authenticating via Windows Account Manager...` for many minutes. The terminal buffer doesn't change. Tempting to kill the process.

**Root cause:** Same hidden-WAM-popup issue as elsewhere, but specifically inside the CLI's S2S step. The CLI is genuinely waiting on a popup you can't see; it has not crashed.

**Recovery if you killed it (we did):**

1. Inspect `a365.generated.config.json` — if `AgenticAppId` is populated, the CLI got past the blocking sub-step before you killed it. Don't re-run `a365 setup all`; it isn't fully idempotent for this stage.
2. Run `a365 create-instance identity -c a365.config.json` to finish the agent-user creation (idempotent — recognises the existing identity).
3. Run `pwsh -NoProfile -File scripts/assign-observability-role.ps1` to put the `OtelWrite` role on the blueprint SP.
4. Re-run the embedded Step 9 / Step 10 logic from `setup-environment.ps1` (mint client-app secret, grant `OtelWrite` to client SP, run `refresh-observability-token.ps1`).
5. Manually flip `ENABLE_A365_OBSERVABILITY_EXPORTER=true` in `env/.env.playground`.

**Prevention:** Don't kill it on first instinct. Watch for the WAM popup behind VS Code (Alt+Tab; check the taskbar). If the buffer truly hasn't changed for ≥3 minutes *and* there's no popup anywhere, then kill and follow the recovery above.

### Stale-buffer trap when monitoring long-running scripts

**Symptom:** `get_terminal_output` (or watching the terminal in VS Code) returns identical text on every poll — looks like the script is hung.

**Root cause:** PowerShell terminal buffers don't always emit incremental output for sub-processes that write to stderr or use carriage-return progress bars. The script is making real progress; the on-screen buffer just isn't reflecting it.

**Resolution:** Before deciding the script is hung, **check the artifact state on disk**:

- Has `a365.generated.config.json` gained new fields (e.g. `AgenticAppId`)?
- Is a new RG appearing in `az group list`?
- Has `env/.env.playground.user` been updated?

If any of those have changed since the script started, it isn't hung — it's mid-step. Wait another minute before killing.

### `AADSTS82001` — blueprint apps cannot use raw client-credentials

**Symptom:** Trying to mint an OBS S2S token via MSAL client-credentials against the **blueprint** app fails with `AADSTS82001: This application is configured as agentic and cannot use the client_credentials grant.`

**Root cause:** Agentic apps in Entra are deliberately barred from the client-credentials flow. They authenticate only via federated credential exchange or OBO. The CLI handles this for the runtime path; local-dev token-mint scripts cannot.

**Resolution (now scripted):** `refresh-observability-token.ps1` uses the **client app** identity (not the blueprint), and `setup-environment.ps1` grants `Agent365.Observability.OtelWrite` to **both** the blueprint SP and the client SP. The client app is allowed to use client_credentials and carries the same role, so the resulting token is accepted by the OBS ingest endpoint.

If you ever see `AADSTS82001` after a teardown → setup, verify Step 9 of setup actually ran:

```powershell
$clientSpId = (az ad sp show --id (az ad app list --display-name procodeagent-cli-app --query '[0].appId' -o tsv) --query id -o tsv)
az rest --method GET --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$clientSpId/appRoleAssignments" --query "value[?appRoleId=='8f71190c-00c8-461d-a63b-f74abde9ba52']"
```

Empty result → re-run `setup-environment.ps1` (idempotent for this step) or run the inline Step 9 block from the recovery guidance above.

### OBS S2S token returns HTTP 403 from the ingest endpoint

**Symptom:** Exporter logs show `POST https://agent365.svc.cloud.microsoft/maven/agent365/agents/<agentId>/traces 403`. Token mints fine; spans build fine; ingest rejects.

**Root cause:** Tenant-side gating. The OBS ingest endpoint requires the tenant to be enrolled in the **Frontier** preview program (or to have A365 GA, which lands May 1, 2026). The dev tenant in this repo is neither.

**Resolution:** Not a code defect. Documented as gap **G9** in [docs/project-scope.md](docs/project-scope.md). Retest on a Frontier-enrolled or GA-licensed tenant. The exporter wiring itself has been validated end-to-end (token resolver, baggage stamping, OTLP POST shape).

### `AUTH_HANDLER_NAME` is not set when `USE_AGENTIC_AUTH=true`

**Symptom:** Flipping `USE_AGENTIC_AUTH=true` in `env/.env.playground` and pressing F5 — the agent runs, but MCP tool calls silently fall back to the no-auth path instead of using agentic OBO. No error, no warning above `INFO`.

**Root cause:** [host_agent_server.py](host_agent_server.py) line 162 reads `os.getenv("AUTH_HANDLER_NAME")` to pick the auth handler at message-handling time. Nothing in `env/.env.playground`, `env/.env.playground.user`, or [m365agents.playground.yml](m365agents.playground.yml) writes that variable. The agentic configuration that *is* present (`agentic_type`, `agentic_scopes`, `AGENTAPPLICATION__USERAUTHORIZATION__HANDLERS__AGENTIC__*`) configures the framework's handler registry, but the host code is still asking for the handler by a name that nobody supplies.

**Resolution:** Add `AUTH_HANDLER_NAME=AGENTIC` to `env/.env.playground` and re-run, **and** ensure the matching `AGENTAPPLICATION__USERAUTHORIZATION__HANDLERS__AGENTIC__*` block is present (today only `.env.template` has it; the Playground env files do not). This is currently a latent defect because we only run with `USE_AGENTIC_AUTH=false` (gap G9 in [docs/project-scope.md](docs/project-scope.md)). It will surface as soon as G2 (Teams installation) unblocks the agentic-auth retest path.

The fix also belongs upstream — either the host code should derive the handler name from the framework registry instead of an env var, or `setup-environment.ps1` should write `AUTH_HANDLER_NAME` and the matching `AGENTAPPLICATION__` block when `USE_AGENTIC_AUTH=true`.

**Root cause:** Tenant-side gating. The OBS ingest endpoint requires the tenant to be enrolled in the **Frontier** preview program (or to have A365 GA, which lands May 1, 2026). The dev tenant in this repo is neither.

**Resolution:** Not a code defect. Documented as gap **G9** in [docs/project-scope.md](docs/project-scope.md). Retest on a Frontier-enrolled or GA-licensed tenant. The exporter wiring itself has been validated end-to-end (token resolver, baggage stamping, OTLP POST shape).

## Key Learnings Summary

1. **Install PowerShell 7+ before running any `a365` commands** — the CLI silently depends on `pwsh` for Graph SDK operations
2. **Use `Set-MgGraphOption -DisableLoginByWAM $true` + custom `-ClientId`** when running Graph commands in VS Code terminals — this is the reliable fix for hidden WAM popups
3. **Agent names: letters and digits only, starting with a letter** — no hyphens, underscores, or dots
4. **Always follow the CLI's permission list**, not the docs — the CLI may require more permissions than documented
5. **Write PowerShell 7 commands to script files** when calling from PS 5.1 — avoids escaping issues
6. **Test locally with Agents Playground, not raw HTTP** — the Bot Framework protocol requires a callback connector
7. **Provision Azure OpenAI in setup scripts** — don't assume users have an existing OpenAI API key
8. **The Observability S2S role is non-blocking for local dev** — console traces work without it; only production A365 backend export requires it
9. **Always purge soft-deleted Cognitive Services accounts after `az group delete`** — otherwise the next setup will hit `FlagMustBeSetForRestore`
10. **Blueprint apps reject client-credentials (`AADSTS82001`)** — local-dev token mints must use the client-app identity, with `OtelWrite` granted to the client SP as well as the blueprint SP
11. **Check artifact state on disk before assuming a script is hung** — terminal buffers can lag real progress by minutes
12. **`SECRET_*` env-file names get re-mapped to un-prefixed names by `m365agents.playground.yml`** — the Python source reads `BEARER_TOKEN`, not `SECRET_BEARER_TOKEN`. See the env-flow table in [docs/design.md](docs/design.md#how-env-variables-flow-into-the-running-agent)
13. **`AUTH_HANDLER_NAME` is currently orphaned** — referenced by `host_agent_server.py` but not written by setup; flipping `USE_AGENTIC_AUTH=true` today silently falls back to no-auth. Latent defect, surfaces with G2 (Teams)

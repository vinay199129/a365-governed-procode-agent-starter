# Setup Walkthrough — What `setup-environment.ps1` Provisions

A stage-by-stage map of every Azure resource, Entra object, role assignment, and local file the setup script creates. Pair this with [code-walkthrough.md](code-walkthrough.md) (which traces request flow) and [scripts/README.md](../scripts/README.md) (which lists every script).

> **Read this when:** you want to know exactly what lands in your tenant before running the script, or you're investigating "what's actually deployed?" after a setup. Each step shows tenant changes plus the file/line in `setup-environment.ps1` that does the work.

---

## Setup at a glance

```
Local machine                          Azure subscription                 Entra tenant
─────────────                          ──────────────────                 ────────────

  Step 0  prerequisites
  Step 1  az account show ────────▶    (read-only)
  Step 1b verified domain  ────────────────────────────────────────▶     (Graph read)

  Step 2  ───────────────────────▶     RG rg-a365-<name>
                                       └─ Cognitive Services
                                          (procodeagent-openai)
                                          └─ deployment gpt-4o-mini

  Step 3  ─────────────────────────────────────────────────────────▶     client app + SP
                                                                          (7 Graph delegated
                                                                           scopes, admin
                                                                           consented)

  Step 4  uv venv / uv sync
  Step 5  env/.env.playground
          env/.env.playground.user

  Step 6  a365 setup all  ─────────────────────────────────────────▶     blueprint app + SP
                                                                          ├─ inheritable
                                                                          │  OAuth grants
                                                                          │  (Graph, WIQ,
                                                                          │   Bot, OBS, PP)
                                                                          └─ S2S role assignments
                                                                             ⚠ WAM popup x2

  Step 7  a365 create-instance ───────────────────────────────────▶     instance app + SP
                                                                          + agentUser (UPN)

  Step 8  assign-observability-role.ps1 ──────────────────────────▶     OtelWrite on blueprint SP

  Step 9  client secret + client SP role ─────────────────────────▶     client app secret
                                                                          + OtelWrite on client SP

  Step 10 refresh-observability-token.ps1
          → SECRET_OBS_S2S_TOKEN
          → flips ENABLE_A365_OBSERVABILITY_EXPORTER=true

  Step 11 (optional, interactive)
          refresh-bearer-token.ps1 ────────────────────────────────▶    delegated token
          → SECRET_BEARER_TOKEN                                          (device code)
```

---

## Step 0 — Prerequisites

**What:** Verifies `pwsh`, `az`, `a365`, `uv`, `dotnet`, `python`, `git` are on PATH. Auto-installs the A365 CLI if missing.
**Side effects:** None.
**File:** [setup-environment.ps1](../scripts/setup-environment.ps1) lines 80-123.

## Step 1 — Azure login

**What:** Runs `az account show`; prompts `az login` if not signed in. Confirms subscription/tenant/user.
**Side effects:** None (read-only).
**File:** lines 125-145.

## Step 1b — Resolve verified tenant domain

**What:** Calls Microsoft Graph (`/v1.0/domains?$filter=isDefault eq true`) to find the operator's verified tenant domain (e.g. `vinay199129gmail.onmicrosoft.com`). Becomes the suffix of the agent UPN later.
**Side effects:** None (read-only Graph call).
**File:** lines 147-159.

## Step 2 — Azure OpenAI provisioning

**What:**
1. Creates **resource group** `rg-a365-<agentname>` in `eastus`.
2. Creates **Cognitive Services account** `<agentname>-openai`, kind `OpenAI`, SKU `S0`.
3. Creates **model deployment** `gpt-4o-mini` (model version `2024-07-18`, SKU `GlobalStandard`, capacity 10).
4. Reads back endpoint + key1 for Step 5.

**Tenant changes:** RG + 1 Cognitive Services account + 1 model deployment.
**File:** lines 161-249.
**Failure modes:** soft-deleted CS shells block recreate-by-name — see [TROUBLESHOOTING.md](../TROUBLESHOOTING.md#cognitive-services-soft-delete-blocks-recreate-by-name).

## Step 3 — Entra client app

**What:**
1. Creates **Entra app registration** `<agentname>-cli-app` with public-client flow + redirect `http://localhost`.
2. Creates the matching **service principal**.
3. Adds **7 delegated Microsoft Graph permissions** (`Application.ReadWrite.All`, `AgentIdentityBlueprint.{ReadWrite,UpdateAuthProperties,AddRemoveCreds}.All`, `DelegatedPermissionGrant.ReadWrite.All`, `Directory.Read.All`, `User.ReadWrite.All`).
4. Grants **admin consent**.

**Tenant changes:** 1 app + 1 SP + admin-consented permissions.
**File:** lines 251-308.

## Step 4 — Python environment

**What:** `uv venv` (idempotent) + `uv sync` to install Python deps from `pyproject.toml`.
**Side effects:** Creates/refreshes `.venv/`. No tenant changes.
**File:** lines 310-327.

## Step 5 — Playground env files

**What:**
- Generates **`env/.env.playground`** with `CLIENT_APP_ID`, `USE_AGENTIC_AUTH=false`, `ENABLE_A365_OBSERVABILITY_EXPORTER=false` (flipped to `true` in Step 10), and the `agentic_*` connection-map placeholders.
- Generates **`env/.env.playground.user`** with the Azure OpenAI key + endpoint + deployment from Step 2, plus empty placeholders for `SECRET_BEARER_TOKEN`, `SECRET_CLIENT_APP_SECRET`, `SECRET_OBS_S2S_TOKEN`.

**Side effects:** Local files only. The `SECRET_*` names get re-mapped to un-prefixed names at runtime — see the env-flow table in [design.md](design.md#how-env-variables-flow-into-the-running-agent).
**File:** lines 329-395.

## Step 6 — A365 blueprint (`a365 setup all`)

The heaviest step — invokes the A365 CLI which, under the covers:

1. Writes **`a365.config.json`** (the blueprint contract — name, scopes, MCP allow-list, agent UPN target).
2. **Registers the blueprint** in the A365 management plane → creates the Entra agentic app + SP behind it.
3. **Mints a client secret** for the blueprint app and stores it in the management plane.
4. **Configures inheritable OAuth grants** on the blueprint SP for: Microsoft Graph, Work IQ Tools (Mail/Calendar MCP), Messaging Bot API, Observability API, Power Platform API.
5. **Configures S2S app role assignments**. ← *this is where the WAM popups appear.* Two interactive sign-ins via Windows Account Manager.
6. Writes `agentBlueprintId` and `agentBlueprintServicePrincipalObjectId` to **`a365.generated.config.json`**.

**Tenant changes:** 1 blueprint Entra app + 1 SP + ~15 OAuth2 grants + S2S role assignments.
**File:** lines 397-441.
**Failure modes:** WAM popups hidden behind VS Code — see [TROUBLESHOOTING.md](../TROUBLESHOOTING.md#a365-setup-all-hangs-on-configuring-s2s-app-role-assignments).

## Step 7 — Primary agent identity (`a365 create-instance identity`)

**What:**
1. Creates a new **agent instance app** (own Entra app + SP) under the blueprint.
2. Creates the **agent user** — an `agentUser` directory object with UPN `<agentname>@<verified-tenant-domain>`, the configured display name, and usage location `US`.
3. Projects the blueprint's delegated scopes onto the instance SP **byte-for-byte**.
4. Writes `AgenticAppId` (instance app id) and `AgenticUserId` (agent-user object id) to `a365.generated.config.json`.

**Tenant changes:** 1 instance Entra app + SP + 1 agent user.
**File:** lines 443-460.
**Note:** Mailbox / OneDrive provisioning happens after license assignment and can take up to 24 hours.

## Step 8 — Blueprint `OtelWrite` role

Invokes [`scripts/assign-observability-role.ps1`](../scripts/assign-observability-role.ps1), which uses **browser auth via the custom client app** (not WAM):

1. Connects to Microsoft Graph with `AppRoleAssignment.ReadWrite.All`.
2. Resolves the Observability resource SP (`appId=9b975845-388f-4429-889e-eab1ef63949c`) and the `Agent365.Observability.OtelWrite` app role (`8f71190c-00c8-461d-a63b-f74abde9ba52`).
3. Assigns that role to the blueprint SP.

**Tenant changes:** 1 app role assignment on the blueprint SP. Idempotent.
**File:** lines 462-479.

## Step 9 — Local-dev S2S bootstrap

Three actions, all on the **client app** (not the blueprint):

1. `az ad app credential reset --display-name "observability-s2s-roundtrip" --append --years 1` → mints a client secret, persists it as `SECRET_CLIENT_APP_SECRET` in `env/.env.playground.user`.
2. POSTs to `/servicePrincipals/{clientSp.id}/appRoleAssignments` to grant `OtelWrite` on the **client SP**.
3. *Why both?* Blueprint apps reject `client_credentials` (`AADSTS82001`); the local-dev token mint in Step 10 has to use the client app's identity, which therefore needs the same role.

**Tenant changes:** 1 client secret on the client app + 1 app role assignment on the client SP.
**File:** lines 481-534.
**Failure modes:** [`AADSTS82001`](../TROUBLESHOOTING.md#aadsts82001--blueprint-apps-cannot-use-raw-client-credentials).

## Step 10 — Mint initial `OBS_S2S_TOKEN`

Invokes [`scripts/refresh-observability-token.ps1`](../scripts/refresh-observability-token.ps1), which:

1. Uses **MSAL `client_credentials`** with `CLIENT_APP_ID` + `SECRET_CLIENT_APP_SECRET`.
2. Mints a token for `https://api.powerplatform.com/.default`.
3. Persists it as `SECRET_OBS_S2S_TOKEN` in `env/.env.playground.user`.
4. Flips `ENABLE_A365_OBSERVABILITY_EXPORTER=true` in `env/.env.playground` since the token is now real.

**Tenant changes:** None (token is just an Entra-issued JWT). TTL ~60 min.
**File:** lines 536-564.

## Step 11 — Bearer token (optional, interactive)

Suggests `pwsh -File .vscode/scripts/refresh-bearer-token.ps1`. That script uses **MSAL device-code flow** (browser, no WAM) to mint a delegated token in the operator's identity, scoped to Work IQ Tools (the MCP audience), and writes it as `SECRET_BEARER_TOKEN`.

**Tenant changes:** None (delegated token). TTL ~4 min — re-run before F5.
**File:** lines 566-580.

---

## Final tenant footprint

```
Azure subscription                                  Entra tenant
──────────────────                                  ────────────

rg-a365-<name>                                      ┌─ Client app  (CLI / local-dev)
└─ Cognitive Services                               │  └─ SP (+OtelWrite role, +secret)
   (<name>-openai)                                  │
   └─ deployment gpt-4o-mini                        ├─ Blueprint app  (governance anchor)
                                                    │  └─ SP (+OtelWrite role)
                                                    │     └─ ~15 OAuth2 delegated grants
                                                    │        (inherited by instances)
                                                    │
                                                    └─ Instance app  (the deployed agent)
                                                       ├─ SP (scopes copied from blueprint)
                                                       └─ agentUser
                                                          UPN: <name>@<tenant domain>
                                                          (mailbox after license, ≤24h)
```

| Object | Count | Lifetime |
|---|---|---|
| Resource group | 1 | Permanent until teardown |
| Azure OpenAI account + deployment | 1 + 1 | Permanent until teardown |
| Entra apps (client + blueprint + instance) | 3 | Permanent until teardown |
| Service principals | 3 | Permanent until teardown |
| Agent user (`agentUser` object) | 1 | Permanent until teardown |
| OAuth2 delegated grants | ~15 across SPs | Permanent until teardown |
| App role assignments (`OtelWrite`) | 2 (blueprint SP + client SP) | Permanent until teardown |
| Client app secret | 1 | 1-year TTL or rotation |
| `OBS_S2S_TOKEN` JWT | 1 | ~60 minutes |
| `BEARER_TOKEN` JWT | 1 | ~4 minutes |

[`teardown-environment.ps1`](../scripts/teardown-environment.ps1) reverses all of the **permanent** ones and additionally **purges the soft-deleted Cognitive Services shell** so the next setup can re-use the same names. The most recent reference round-trip is captured in [evidence/round-trip.md](evidence/round-trip.md).

---

## Mapping back to the runtime

| Setup artifact | Runtime usage in code |
|---|---|
| `agentBlueprintId` | Inherited posture; not directly read by the agent |
| `AgenticAppId` | Stamped on every activity as `recipient.agentic_app_id` → consumed by [host_agent_server.py](../host_agent_server.py) Stage E.1 |
| `AgenticUserId` | The runtime identity of the agent (mailbox, Teams presence) |
| `CLIENT_APP_ID` + `SECRET_CLIENT_APP_SECRET` | Used by `refresh-observability-token.ps1` to mint `OBS_S2S_TOKEN` |
| `SECRET_OBS_S2S_TOKEN` → runtime `OBS_S2S_TOKEN` | Fallback in `agent.py:token_resolver` (Playground path) |
| `SECRET_BEARER_TOKEN` → runtime `BEARER_TOKEN` | Read by `local_authentication_options.py`; Priority 2 in the MCP auth ladder ([code-walkthrough.md](code-walkthrough.md#stage-g--mcp-server-setup-agentpysetup_mcp_servers)) |
| Azure OpenAI key + endpoint | `agent.py` constructor — selects `AsyncAzureOpenAI` over `AsyncOpenAI` |

For the request-side counterpart of this doc, see [code-walkthrough.md](code-walkthrough.md).

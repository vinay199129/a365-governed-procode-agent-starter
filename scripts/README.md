# Scripts

Automation for provisioning, configuring, exercising, and tearing down the A365 Governed Pro-Code Agent Starter.

All scripts are PowerShell 7+ (`pwsh`) and must be run from the **repository root**.

## Quick reference

| Script | Purpose | When to run |
|---|---|---|
| [setup-environment.ps1](setup-environment.ps1) | Single-command bootstrap. Provisions Azure OpenAI + model deployment, the Entra client app, the A365 blueprint + primary instance, mints the observability S2S token, and writes both `env/.env.playground` and `env/.env.playground.user`. Narrated with `Write-Stage` banners so you can follow what it's doing. | Day-0, or any time you want a clean slate after `teardown-environment.ps1`. |
| [teardown-environment.ps1](teardown-environment.ps1) | Reverse of setup: deletes the A365 blueprint registration + instance, the Entra client app, agent users, the Azure resource group **synchronously**, and **purges any soft-deleted Cognitive Services accounts** so the next setup can re-use the same names. | Before re-running setup, or to leave the tenant clean. |
| [assign-observability-role.ps1](assign-observability-role.ps1) | Assigns `Agent365.Observability.OtelWrite` to the **blueprint** service principal. Bypasses WAM (browser auth via the custom client app) so it works reliably in VS Code terminals. Idempotent. | Once after `setup-environment.ps1`. Already invoked by setup; available to re-run after a policy change. |
| [refresh-observability-token.ps1](refresh-observability-token.ps1) | Mints the **OBS S2S token** used by the OpenTelemetry exporter and writes it to `env/.env.playground.user` as `SECRET_OBS_S2S_TOKEN`. Uses the **client-app** identity + a client secret (blueprint apps cannot use raw client-credentials — `AADSTS82001`). | Whenever the existing `SECRET_OBS_S2S_TOKEN` expires (~1 h), or after rotating `SECRET_CLIENT_APP_SECRET`. |
| [provision-second-instance.ps1](provision-second-instance.ps1) | Creates a second agent instance under the same blueprint to demonstrate posture inheritance (success criteria S4 / S5). Generates the evidence artifact at `docs/evidence/multi-instance-inheritance.md`. | Optional — demo / G5 closure. |
| [smoke-test.ps1](smoke-test.ps1) | Posts a synthetic Bot Framework message to a locally running agent (`http://localhost:3978/api/messages`) for fast end-to-end smoke checks without launching Playground. | While the agent is running locally and you want to validate `/api/messages` outside of Playground. |
| [build_manifests.py](build_manifests.py) | Regenerates `assets/js/docs-manifest.js` and `assets/js/posts-manifest.js` from the markdown files on disk under `docs/` and `posts/`. The pytest suite fails if these are stale, so re-run any time you add, rename, or remove a doc or post. | After adding/renaming/removing markdown files under `docs/` or `posts/`. |
| [.vscode/scripts/refresh-bearer-token.ps1](../.vscode/scripts/refresh-bearer-token.ps1) | **Interactive device-code login** that mints the short-lived (~4 min) `SECRET_BEARER_TOKEN` Playground uses on the first user turn. Bypasses WAM completely. | Right before pressing F5, or when Playground returns 401 on the first message. |

## Prerequisites

- PowerShell 7+ (`pwsh`)
- Azure CLI (`az`) signed in — `az login`
- A365 CLI installed
- `Microsoft.Graph.Authentication` module (provides the MSAL DLL used by `refresh-bearer-token.ps1` and `assign-observability-role.ps1`)
- Permissions to create Entra app registrations, assign app roles, and create Azure resources in the target subscription

## Common workflows

### First-time setup

```pwsh
pwsh -NoProfile -File scripts/setup-environment.ps1
# Two WAM popups will appear during 'a365 setup all' — accept both as your tenant admin.
# Setup ends with a 'Step 11 (optional)' nudge for the bearer token.

pwsh -NoProfile -File .vscode/scripts/refresh-bearer-token.ps1   # right before F5
```

### Round-trip (clean slate)

This is the reproducibility test — run it any time you change provisioning logic and want to prove it still lands.

```pwsh
pwsh -NoProfile -File scripts/teardown-environment.ps1 -SkipConfirmation
pwsh -NoProfile -File scripts/setup-environment.ps1
```

The latest reference run is captured in [docs/evidence/round-trip.md](../docs/evidence/round-trip.md), including identifiers, per-step outcomes, and the two manual touch-points (WAM popups + optional bearer device-code).

### Re-mint expired tokens

```pwsh
# OBS S2S (1-hour TTL)
pwsh -NoProfile -File scripts/refresh-observability-token.ps1

# Bearer (4-minute TTL — devicecode flow, only needed before F5)
pwsh -NoProfile -File .vscode/scripts/refresh-bearer-token.ps1
```

### Demo posture inheritance (optional)

```pwsh
pwsh -NoProfile -File scripts/provision-second-instance.ps1
# Updates docs/evidence/multi-instance-inheritance.md with both instances' identifiers
# and Graph-side scope/role parity proof.
```

## What each script writes

| Script | Files touched | Tenant-side effects |
|---|---|---|
| `setup-environment.ps1` | `a365.config.json`, `a365.generated.config.json`, `env/.env.playground`, `env/.env.playground.user` | RG `rg-a365-<name>`, Azure OpenAI account + deployment, Entra client app, A365 blueprint + primary instance, agent user, OAuth2 grants, `OtelWrite` on blueprint SP **and** on client SP |
| `teardown-environment.ps1` | Removes `a365.generated.config.json` (keeps `a365.config.json`) | Deletes the RG (sync), purges soft-deleted Cognitive Services accounts, deletes the Entra client app, deletes agent users, removes blueprint registration |
| `assign-observability-role.ps1` | None | `OtelWrite` on blueprint SP |
| `refresh-observability-token.ps1` | `env/.env.playground.user` (`SECRET_OBS_S2S_TOKEN`, optionally `SECRET_CLIENT_APP_SECRET`) | None |
| `refresh-bearer-token.ps1` | `env/.env.playground.user` (`SECRET_BEARER_TOKEN`) | None |
| `provision-second-instance.ps1` | `docs/evidence/multi-instance-inheritance.md` | Second agent instance + agent user under the existing blueprint |
| `smoke-test.ps1` | None | None |

## Troubleshooting

If a script fails, check [TROUBLESHOOTING.md](../TROUBLESHOOTING.md) — every known failure mode (WAM popups, soft-delete recreate, AADSTS82001 on blueprint apps, PowerShell 5.1 escaping) is documented there with a verified fix.

For comment-based help on any individual script:

```pwsh
Get-Help scripts/<script>.ps1 -Full
```
# Scripts

Automation for provisioning, configuring, and tearing down the A365 Governed Pro-Code Agent Starter.

All scripts are PowerShell 7+ (`pwsh`) and must be run from the repository root.

## Execution order

| Step | Script | Purpose | When to run |
|---|---|---|---|
| 1 | [setup-environment.ps1](setup-environment.ps1) | Provision Azure OpenAI + deployment, Entra client app, A365 blueprint + instance, and generate `.env` files | Day-0 bootstrap |
| 2 | [assign-observability-role.ps1](assign-observability-role.ps1) | Grant the `Agent365.Observability.OtelWrite` app role to the blueprint service principal | Once, after step 1 |
| 3 | [provision-second-instance.ps1](provision-second-instance.ps1) | Create a second agent instance under the same blueprint to demonstrate posture inheritance (G5/G7) | Optional demo |
| 99 | [teardown-environment.ps1](teardown-environment.ps1) | Remove A365 blueprint + instance, Entra app, Azure resource group, and local config files | Cleanup |

## Prerequisites

- PowerShell 7+ (`pwsh`)
- Azure CLI (`az`) signed in — `az login`
- A365 CLI installed
- Microsoft.Graph PowerShell module (required by `assign-observability-role.ps1`)
- Permissions to create Entra app registrations and assign app roles in the target tenant

## Usage

```pwsh
# 1. Provision everything
pwsh -NoProfile -File scripts/setup-environment.ps1

# 2. Grant observability role to the blueprint
pwsh -NoProfile -File scripts/assign-observability-role.ps1

# 3. (Optional) Prove inheritance with a second instance
pwsh -NoProfile -File scripts/provision-second-instance.ps1

# 99. Tear everything down
pwsh -NoProfile -File scripts/teardown-environment.ps1
```

See each script's comment-based help (`Get-Help <script.ps1> -Full`) for parameters and examples.

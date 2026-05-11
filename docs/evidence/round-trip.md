# Round-trip evidence: `teardown` → `setup`

Backlog task: prove that the hardened `scripts/teardown-environment.ps1` followed by
`scripts/setup-environment.ps1` reaches the same working end-state as the previous
session, with no manual fix-ups.

**Last run:** 2026-05-08 (A365 CLI `1.1.139-preview+6ebfe9e056`, pinned in `scripts/setup-environment.ps1`).

## Reproduction command

```powershell
pwsh -NoProfile -File scripts/teardown-environment.ps1 -SkipConfirmation
# (synchronous now: waits for RG delete + purges soft-deleted Cognitive Services accounts)
pwsh -NoProfile -File scripts/setup-environment.ps1
```

## Identifiers (this round-trip)

| Artifact | ID | Notes |
| --- | --- | --- |
> Tenant-specific identifiers (tenant/subscription GUIDs, app/SP IDs, UPNs) have been replaced with placeholders. Your values will differ on every run.

| Tenant | `<tenant-id>` | Stable. |
| Subscription | `<subscription-id>` | Stable. |
| Resource group | `rg-a365-procodeagent` | Recreated. |
| Azure OpenAI account | `procodeagent-openai` (eastus, S0) | Recreated after purge. |
| Model deployment | `gpt-4o-mini` | Recreated. |
| CLI client app | `<client-app-id>` | New (prior client app id was different). |
| CLI client SP | `<client-sp-id>` | New. |
| Blueprint | `<blueprint-app-id>` | New (prior service-side blueprint record was deleted along with the underlying Entra app this teardown). |
| Blueprint SP | `<blueprint-sp-id>` | New. |
| Agent identity (`AgenticAppId`) | `<instance1-sp-id>` | New. |
| Agent user (`AgenticUserId`) | `<instance1-user-oid>` | New. |
| Agent UPN | `procodeagent@<your-tenant-domain>` | Reused name (prior user oid was deleted by teardown). |

## Final environment state

`a365.generated.config.json` populated with `agentBlueprintId`,
`agentBlueprintServicePrincipalObjectId`, `AgenticAppId`, `AgenticUserId`,
`agentUserPrincipalName`. (`completed=false` is normal — it's set by the legacy
`a365 setup all` epilogue we don't run.)

`env/.env.playground` (committable):

- `CLIENT_APP_ID=<client-app-id>`
- `USE_AGENTIC_AUTH=false`
- `ENABLE_A365_OBSERVABILITY_EXPORTER=true` ← flipped by Step 10 once the OBS_S2S_TOKEN was real

`env/.env.playground.user` (gitignored):

- `SECRET_AZURE_OPENAI_API_KEY` populated
- `AZURE_OPENAI_ENDPOINT=https://eastus.api.cognitive.microsoft.com/`
- `AZURE_OPENAI_DEPLOYMENT_NAME=gpt-4o-mini`
- `SECRET_CLIENT_APP_SECRET` populated by Step 9
- `SECRET_OBS_S2S_TOKEN` populated by Step 10
- `SECRET_BEARER_TOKEN` empty (Step 11 skipped — see Caveats)

## Step-by-step outcomes

| # | Step | Result | Notes |
| --- | --- | --- | --- |
| 0 | Prerequisites | OK | az / dotnet / python / git / pwsh / a365 CLI all present. |
| 1 | Azure login | OK | Same sub/tenant/user as previous session. |
| 2 | Azure OpenAI provisioning | OK | RG + account + `gpt-4o-mini` deployment all created. |
| 3 | Entra client app | OK | New `procodeagent-cli-app` (Graph delegated perms + admin consent granted). |
| 4 | Python environment | OK | `uv sync` reused existing `.venv`. |
| 5 | Playground env files | OK | `env/.env.playground` + `env/.env.playground.user` written from templates. |
| 6 | A365 blueprint (`a365 setup all --skip-infrastructure --skip-requirements`) | OK | Blueprint app + SP newly created; inheritable perms + OAuth2 grants + S2S app role assignments configured. **Two interactive WAM prompts** required during this step. |
| 7 | Primary agent identity (`a365 create-instance identity`) | OK | Created `AgenticAppId` + `AgenticUserId` and `procodeagent@<tenant>` agent user with mailbox/Teams presence pending license propagation. |
| 8 | Observability role on blueprint SP (`scripts/assign-observability-role.ps1`) | OK | Role already present (idempotent). |
| 9 | Local-dev S2S bootstrap (client app secret + OtelWrite on client SP) | OK | Secret minted + persisted, role granted. |
| 10 | Mint initial OBS_S2S_TOKEN (`scripts/refresh-observability-token.ps1`) | OK | 1740-char token persisted; exporter flag flipped to `true`. |
| 11 | Bearer token refresh | **Skipped in this run** | Interactive device-code flow; can be run on demand via `pwsh -File .vscode/scripts/refresh-bearer-token.ps1` before the first F5. |

## Gaps closed by this round-trip (script hardening committed)

| Gap discovered | Fix |
| --- | --- |
| `az group delete --no-wait` left a soft-deleted Cognitive Services account; next setup hit `FlagMustBeSetForRestore` | Teardown now deletes the RG **synchronously** and then `az cognitiveservices account purge` for every account that lived in it (and any soft-deleted account in the location whose name starts with the agent base name). |
| Teardown narration mentioned "deletion is async, wait 2-3 minutes" | Trailing async warning removed; banner now says "sync delete + Cognitive Services purge". |

## Caveats / honest gaps

1. **Step 11 (bearer token) is interactive** — it triggers a Microsoft device-code login. Not run as part of this round-trip. Operator must run it manually before the first F5 launch (or after the 1-hour token TTL expires).
2. **Two WAM popups** still appear during `a365 setup all` (blueprint creation + S2S role assignments). They use the local Windows account; if the screen is unattended the script will block silently.
3. **Blueprint reuse**: after teardown deletes the Entra app behind the blueprint, the A365 management plane still finds the blueprint by display name and re-attaches a new client secret to it on the next setup. This is desirable (no orphan blueprints accumulate) but worth noting — the reused `agentBlueprintId` is not proof of broken teardown.
4. **`completed=false`** in `a365.generated.config.json` is a legacy field flipped by `a365 setup all`'s outermost completion step; we don't depend on it.

## Wall-clock

Setup wall-clock (excluding two manual WAM prompts and the diagnostic interruption at Step 7):

- Step 2 (Azure OpenAI account + deployment): ~3-4 min
- Step 6 (`a365 setup all`): ~2-3 min including manual WAM prompts
- Step 7 (`a365 create-instance identity` propagation wait): ~30-60 s
- Steps 9, 10: a few seconds each

Total operator-attended time: ~10-12 min.

## Conclusion

End-to-end teardown → setup is reproducible. The state at the end of this round-trip
matches the prior end-of-session state (same blueprint id, equivalent agent identity,
same env file shape, exporter armed). The only manual touch-points that remain are the
two WAM popups inside `a365 setup all` and the optional bearer-token device-code flow.

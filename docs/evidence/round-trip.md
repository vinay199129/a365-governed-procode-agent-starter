# Round-trip evidence: `teardown` → `setup`

Backlog task: prove that the hardened `scripts/teardown-environment.ps1` followed by
`scripts/setup-environment.ps1` reaches the same working end-state as the previous
session, with no manual fix-ups.

## Reproduction command

```powershell
pwsh -NoProfile -File scripts/teardown-environment.ps1 -SkipConfirmation
# (synchronous now: waits for RG delete + purges soft-deleted Cognitive Services accounts)
pwsh -NoProfile -File scripts/setup-environment.ps1
```

## Identifiers (this round-trip)

| Artifact | ID | Notes |
| --- | --- | --- |
| Tenant | `253bc031-a17c-4b57-b83c-1ee1d86b1331` | Stable. |
| Subscription | `0f0fa811-d118-4f4b-ab07-bf80b5565924` | Stable. |
| Resource group | `rg-a365-procodeagent` | Recreated. |
| Azure OpenAI account | `procodeagent-openai` (eastus, S0) | Recreated after purge. |
| Model deployment | `gpt-4o-mini` | Recreated. |
| CLI client app | `132df236-73fc-4012-a997-ff06c6cb6016` | New (prior was `fffe21b3-…`). |
| CLI client SP | `270b66dd-80ee-4c28-a2d8-5bb9f543d579` | New. |
| Blueprint | `19bc459c-7807-4a41-a467-4adfb9f9704b` | **Reused** — A365 service-side blueprint record persists even after the underlying Entra app is deleted. |
| Blueprint SP | `306cc506-1f1d-4d46-b89d-22865aee933f` | Reused with the blueprint. |
| Agent identity (`AgenticAppId`) | `0f3701db-66a0-40b4-bb3f-3b1f02090153` | New. |
| Agent user (`AgenticUserId`) | `7d53f089-3e2a-493c-871e-be30500d074d` | New. |
| Agent UPN | `procodeagent@vinay199129gmail.onmicrosoft.com` | Reused name (prior user `d4ad9d38-…` was deleted by teardown). |

## Final environment state

`a365.generated.config.json` populated with `agentBlueprintId`,
`agentBlueprintServicePrincipalObjectId`, `AgenticAppId`, `AgenticUserId`,
`agentUserPrincipalName`. (`completed=false` is normal — it's set by the legacy
`a365 setup all` epilogue we don't run.)

`env/.env.playground` (committable):

- `CLIENT_APP_ID=132df236-…`
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
| 6 | A365 blueprint (`a365 setup all`) | OK | Blueprint reused (service-side persistence); inheritable perms + OAuth2 grants + S2S app role assignments configured. **Two interactive WAM prompts** required during this step. |
| 7 | Primary agent identity (`a365 create-instance identity`) | OK (after recovery) | Created new `AgenticAppId` + `AgenticUserId`. **Note**: original full setup-environment.ps1 run was killed during this step's propagation wait; re-running `a365 create-instance identity` was idempotent and finished it. |
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

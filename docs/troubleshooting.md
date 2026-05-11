# Troubleshooting

The full troubleshooting reference — known failure modes and one-line
fixes — lives at the repo root in
[`TROUBLESHOOTING.md`](https://github.com/vinay199129/a365-governed-procode-agent-starter/blob/main/TROUBLESHOOTING.md).

## Quick checks

If something failed, run through this list before re-running setup:

1. **`pwsh --version` ≥ 7.4** — the A365 CLI requires PowerShell 7.
2. **`az account show`** — confirm the right subscription and tenant.
3. **`a365 --version`** — confirm the A365 CLI is installed and signed in.
4. **Bearer token freshness** — the token Playground uses has a 4-minute
   TTL. Always re-run `refresh-bearer-token.ps1` immediately before F5.
5. **Two WAM popups during `a365 setup all`** — both must be accepted.
   If you missed one, re-run `setup-environment.ps1`.

## Common symptoms

| Symptom | Likely cause |
| --- | --- |
| `401 Unauthorized` on first Playground turn | Bearer token expired — refresh it |
| OTel export shows `403 Forbidden` | Tenant not enrolled in [Frontier](https://adoption.microsoft.com/copilot/frontier-program/) — AI-teammate-tier ingest is Frontier-gated at GA |
| All MCP servers return `500 Internal Server Error`; bot answers from LLM only ("I don't have access…") | Bearer token belongs to an unlicensed user (guest, MSA, no M365 license). Sign in as a licensed work/school account in the same tenant. See [TROUBLESHOOTING.md → MCP servers all return HTTP 500](https://github.com/vinay199129/a365-governed-procode-agent-starter/blob/main/TROUBLESHOOTING.md#mcp-servers-all-return-http-500-mcp_mailtools-mcp_calendartools-etc) |
| `setup-environment.ps1` hangs at WAM popup | Popup is behind another window — alt-tab |
| Agent identity not visible in Entra | Setup didn't reach step 5; re-run setup |
| Playground shows blank response | Check terminal for `Activity received`; if missing, the host didn't start — check the F5 launch config |

For each symptom's full diagnosis and fix, open the
[full troubleshooting doc](https://github.com/vinay199129/a365-governed-procode-agent-starter/blob/main/TROUBLESHOOTING.md).

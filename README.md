# A365 Governed Pro-Code Agent Starter

A reference **pro-code agent** that integrates with **Microsoft Agent 365 (A365)** as the enterprise governance layer — no Copilot Studio dependency. This starter demonstrates:

- **Governance**: A365 Security Blueprint with automatic posture inheritance across agent instances
- **Identity**: Entra-backed agent identity with tenant-owned UPN and Teams presence
- **Observability**: End-to-end OpenTelemetry tracing to the A365 backend
- **Notifications**: Services and models for managing user notifications
- **Tools**: Model Context Protocol (MCP) tools for Mail and Calendar
- **Hosting Patterns**: Hosting with the Microsoft 365 Agents SDK

The starter uses the [Microsoft Agent 365 SDK for Python](https://github.com/microsoft/Agent365-python).

> **🌐 Documentation site:** <https://vinay199129.github.io/a365-governed-procode-agent-starter/>
>
> A polished Docusaurus site with hero landing, sidebar nav, and a
> guided learning series ships with the repo under [`website/`](website/).
> It auto-deploys to GitHub Pages on push to `main` — see
> [`website/README.md`](website/README.md) for local preview and config.

For deeper context, see:

- [docs/learning-guide.md](docs/learning-guide.md) — Concept-first A365 walkthrough with links to the official docs
- [docs/code-walkthrough.md](docs/code-walkthrough.md) — Stage-by-stage trace of a request from F5 to a response (with diagrams)
- [docs/setup-walkthrough.md](docs/setup-walkthrough.md) — Stage-by-stage map of what `setup-environment.ps1` provisions (with diagrams)
- [docs/project-scope.md](docs/project-scope.md) — Scope, success criteria, gap analysis (read the **TL;DR** at the top for current status)
- [docs/blueprint-policy.md](docs/blueprint-policy.md) — Security Blueprint policy set
- [docs/design.md](docs/design.md) — Runtime + governance-plane architecture
- [docs/evidence/](docs/evidence/) — Captured proof for success criteria (multi-instance inheritance, teardown→setup round-trip)
- [scripts/README.md](scripts/README.md) — What every automation script does and when to run it
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) — Known failure modes and resolutions

For general A365 developer documentation, visit [Microsoft Agent 365 Developer Documentation](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/).

## Quickstart

```pwsh
# 1. Provision Azure OpenAI + Entra client app + A365 blueprint + agent identity + tokens.
#    Narrated step-by-step. Two WAM popups will appear inside `a365 setup all`; accept them.
pwsh -NoProfile -File scripts/setup-environment.ps1

# 2. Mint the short-lived bearer token Playground needs on the first turn (interactive device-code).
pwsh -NoProfile -File .vscode/scripts/refresh-bearer-token.ps1

# 3. Open the M365 Agents Toolkit panel in VS Code, then press F5 → Debug in Microsoft 365 Agents Playground.
```

To wipe the tenant and start over (the round-trip reproducibility test):

```pwsh
pwsh -NoProfile -File scripts/teardown-environment.ps1 -SkipConfirmation
pwsh -NoProfile -File scripts/setup-environment.ps1
```

The most recent reference round-trip with identifiers and per-step outcomes is in [docs/evidence/round-trip.md](docs/evidence/round-trip.md).

## Prerequisites

To run this starter on your local dev machine you will need:

- [Python 3.11+](https://www.python.org/)
- [Microsoft 365 Agents Toolkit](https://aka.ms/teams-toolkit) VS Code extension (latest)
- Azure OpenAI or OpenAI API credentials
- Azure CLI signed in via `az login`
- PowerShell 7+ (`pwsh`) — required by the A365 CLI; see [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
- A365 CLI — required for blueprint + agent identity provisioning

The following SDKs are pulled in automatically by `pyproject.toml`:

- Microsoft Agent 365 SDK
- Microsoft 365 Agents SDK
- OpenAI Agents SDK (`openai-agents`)

## Python Environment Configuration

Set up the Python virtual environment manually before running the agent or deploy steps:

1. Install `uv`:
	- `pip install uv`
2. Create a virtual environment:
	- `uv venv`
3. Activate the virtual environment:
	- Windows PowerShell: `.venv\Scripts\Activate.ps1`
	- macOS/Linux: `source .venv/bin/activate`

## Working with User Identity

On every incoming message, the A365 platform populates `activity.from_property` with basic user
information — always available with no API calls or token acquisition:

| Field | Description |
|---|---|
| `activity.from_property.id` | Channel-specific user ID (e.g., `29:1AbcXyz...` in Teams) |
| `activity.from_property.name` | Display name as known to the channel |
| `activity.from_property.aad_object_id` | Azure AD Object ID — use this to call Microsoft Graph |

The sample logs these fields at the start of every message turn and injects the display name
into the LLM system instructions for personalized responses.

## Running the Agent in Microsoft 365 Agents Playground

If you ran the [Quickstart](#quickstart), all four env-file values below are already populated. Skip to step 5.

1. Select the Microsoft 365 Agents Toolkit icon on the left in the VS Code toolbar.
1. In *env/.env.playground.user*, set your Azure OpenAI key `SECRET_AZURE_OPENAI_API_KEY`, endpoint `AZURE_OPENAI_ENDPOINT`, and deployment name `AZURE_OPENAI_DEPLOYMENT_NAME` (or `SECRET_OPENAI_API_KEY` if using OpenAI direct).
1. In *env/.env.playground*, set `CLIENT_APP_ID` to the Entra client app id created by `scripts/setup-environment.ps1`.
1. Run `pwsh -NoProfile -File .vscode/scripts/refresh-bearer-token.ps1` to mint a fresh `SECRET_BEARER_TOKEN` (4-minute TTL — do this immediately before F5).
1. Press F5 to start debugging. Select **Debug in Microsoft 365 Agents Playground**.
1. Send any message to get a response from the agent.

**Congratulations** — you are running an agent that can interact with users in Microsoft 365 Agents Playground.

## Handling Agent Install and Uninstall

When a user installs (hires) or uninstalls (removes) the agent, the A365 platform sends an `InstallationUpdate` activity — also referred to as the `agentInstanceCreated` event. The sample handles this in `on_installation_update` in `host_agent_server.py`:

| Action | Description |
|---|---|
| `add` | Agent was installed — send a welcome message |
| `remove` | Agent was uninstalled — send a farewell message |

```python
if action == "add":
    await context.send_activity("Thank you for hiring me! Looking forward to assisting you in your professional journey!")
elif action == "remove":
    await context.send_activity("Thank you for your time, I enjoyed working with you.")
```

To test with Agents Playground, use **Mock an Activity → Install application** to send a simulated `installationUpdate` activity.

## Sending Multiple Messages in Teams

Agent365 agents can send multiple discrete messages in response to a single user prompt. This is the recommended pattern for agentic identities in Teams.

> **Important**: Streaming (SSE) is not supported for agentic identities in Teams. The SDK detects agentic identity and buffers streaming into a single message. Instead, call `send_activity` multiple times to send multiple messages.

### Pattern

1. Send an immediate acknowledgment so the user knows work has started
2. Run a typing indicator loop — each indicator times out after ~5 seconds, so re-send every ~4 seconds
3. Do your LLM work, then send the response

### Typing Indicators

- Typing indicators show a progress animation in Teams
- They have a built-in ~5-second visual timeout
- For long-running operations, re-send the typing indicator in a loop every ~4 seconds
- Typing indicators are only visible in 1:1 chats and small group chats (not channels)

### Code Example

```python
# Multiple messages: send an immediate ack before the LLM work begins.
# Each send_activity call produces a discrete Teams message.
await context.send_activity("Got it — working on it…")

# Send typing indicator immediately (awaited so it arrives before the LLM call starts).
await context.send_activity(Activity(type="typing"))

# Background loop refreshes the "..." animation every ~4s (it times out after ~5s).
# asyncio.create_task is used because all aiohttp handlers share the same event loop.
async def _typing_loop():
    while True:
        try:
            await asyncio.sleep(4)
            await context.send_activity(Activity(type="typing"))
        except asyncio.CancelledError:
            break

typing_task = asyncio.create_task(_typing_loop())
try:
    response = await agent.invoke(user_message)
    await context.send_activity(response)
finally:
    typing_task.cancel()
    try:
        await typing_task
    except asyncio.CancelledError:
        pass
```

## Running the Agent

To set up and test this agent, refer to the [Configure Agent Testing](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/testing?tabs=python) guide for complete instructions.

## Support

For issues, questions, or feedback:

- **Issues**: File issues in the [GitHub Issues](https://github.com/microsoft/Agent365-python/issues) section
- **Documentation**: See the [Microsoft Agents 365 Developer documentation](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/)

## Contributing

This project welcomes contributions and suggestions. Most contributions require you to agree to a Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us the rights to use your contribution. For details, visit <https://cla.opensource.microsoft.com>.

When you submit a pull request, a CLA bot will automatically determine whether you need to provide a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/). For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.

## Additional Resources

- [Microsoft Agent 365 SDK - Python repository](https://github.com/microsoft/Agent365-python)
- [Microsoft 365 Agents SDK - Python repository](https://github.com/Microsoft/Agents-for-python)
- [OpenAI API documentation](https://platform.openai.com/docs/)
- [Python API documentation](https://learn.microsoft.com/python/api/?view=m365-agents-sdk&preserve-view=true)

## Trademarks

*Microsoft, Windows, Microsoft Azure and/or other Microsoft products and services referenced in the documentation may be either trademarks or registered trademarks of Microsoft in the United States and/or other countries. The licenses for this project do not grant you rights to use any Microsoft names, logos, or trademarks. Microsoft's general trademark guidelines can be found at http://go.microsoft.com/fwlink/?LinkID=254653.*

## License

Copyright (c) Microsoft Corporation. All rights reserved.

Licensed under the MIT License.

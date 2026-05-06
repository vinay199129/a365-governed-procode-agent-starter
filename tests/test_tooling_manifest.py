"""Schema-shape tests for ToolingManifest.json.

Catches typos and missing fields before they fail at MCP load time during F5.
Does not call out to A365 — pure JSON validation.
"""

import json
from pathlib import Path

import pytest

MANIFEST_PATH = Path(__file__).resolve().parent.parent / "ToolingManifest.json"

REQUIRED_SERVER_FIELDS = {
    "mcpServerName",
    "mcpServerUniqueName",
    "url",
    "scope",
    "audience",
}

EXPECTED_AUDIENCE = "ea9ffc3e-8a23-4a7d-836d-234d7c7565c1"
EXPECTED_URL_PREFIX = "https://agent365.svc.cloud.microsoft/agents/servers/"


@pytest.fixture(scope="module")
def manifest():
    return json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))


def test_manifest_file_exists():
    assert MANIFEST_PATH.exists(), f"ToolingManifest.json not found at {MANIFEST_PATH}"


def test_manifest_has_mcp_servers_list(manifest):
    assert "mcpServers" in manifest
    assert isinstance(manifest["mcpServers"], list)
    assert len(manifest["mcpServers"]) > 0


def test_each_server_has_required_fields(manifest):
    for server in manifest["mcpServers"]:
        missing = REQUIRED_SERVER_FIELDS - server.keys()
        assert not missing, f"Server {server.get('mcpServerName')} missing fields: {missing}"


def test_unique_names_are_unique(manifest):
    names = [s["mcpServerUniqueName"] for s in manifest["mcpServers"]]
    assert len(names) == len(set(names)), f"Duplicate mcpServerUniqueName entries: {names}"


def test_all_servers_target_a365_audience(manifest):
    for server in manifest["mcpServers"]:
        assert server["audience"] == EXPECTED_AUDIENCE, (
            f"{server['mcpServerName']} has unexpected audience {server['audience']}"
        )


def test_all_urls_use_a365_endpoint(manifest):
    for server in manifest["mcpServers"]:
        assert server["url"].startswith(EXPECTED_URL_PREFIX), (
            f"{server['mcpServerName']} URL {server['url']} does not target the A365 MCP endpoint"
        )


def test_scope_pattern_matches_mcp_convention(manifest):
    for server in manifest["mcpServers"]:
        scope = server["scope"]
        assert scope.startswith("McpServers.") and scope.endswith(".All"), (
            f"{server['mcpServerName']} scope '{scope}' does not match McpServers.<X>.All"
        )

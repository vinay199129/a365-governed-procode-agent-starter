"""Unit tests for token_cache.

Verifies the cache key composition and the miss path that the observability
token resolver relies on. The cache is module-level state so each test
clears it explicitly.
"""

import token_cache


def setup_function(_fn):
    token_cache._agentic_token_cache.clear()


def test_get_returns_none_when_empty():
    assert token_cache.get_cached_agentic_token("tenant-a", "agent-1") is None


def test_cache_then_retrieve_round_trip():
    token_cache.cache_agentic_token("tenant-a", "agent-1", "tok-xyz")
    assert token_cache.get_cached_agentic_token("tenant-a", "agent-1") == "tok-xyz"


def test_cache_keys_are_namespaced_by_tenant_and_agent():
    token_cache.cache_agentic_token("tenant-a", "agent-1", "tok-A1")
    token_cache.cache_agentic_token("tenant-b", "agent-1", "tok-B1")

    assert token_cache.get_cached_agentic_token("tenant-a", "agent-1") == "tok-A1"
    assert token_cache.get_cached_agentic_token("tenant-b", "agent-1") == "tok-B1"
    assert token_cache.get_cached_agentic_token("tenant-a", "agent-2") is None


def test_cache_overwrites_existing_token():
    token_cache.cache_agentic_token("tenant-a", "agent-1", "old")
    token_cache.cache_agentic_token("tenant-a", "agent-1", "new")
    assert token_cache.get_cached_agentic_token("tenant-a", "agent-1") == "new"

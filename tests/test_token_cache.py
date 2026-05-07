"""Unit tests for token_cache.

Verifies the cache key composition, TTL handling, and the miss path that the
observability token resolver relies on. The cache is module-level state so
each test clears it explicitly.
"""

import base64
import json
import time

import token_cache


def setup_function(_fn):
    token_cache.cache_clear()


def _make_jwt(exp_unix: float) -> str:
    """Build a JWT-shaped string with a forged `exp` claim. Signature is junk —
    the cache only parses the payload, never verifies the signature."""
    header = base64.urlsafe_b64encode(b'{"alg":"none","typ":"JWT"}').rstrip(b"=").decode()
    payload = base64.urlsafe_b64encode(
        json.dumps({"exp": exp_unix}).encode()
    ).rstrip(b"=").decode()
    return f"{header}.{payload}.sig"


def test_get_returns_none_when_empty():
    assert token_cache.get_cached_agentic_token("tenant-a", "agent-1") is None


def test_cache_then_retrieve_round_trip():
    token = _make_jwt(time.time() + 3600)
    token_cache.cache_agentic_token("tenant-a", "agent-1", token)
    assert token_cache.get_cached_agentic_token("tenant-a", "agent-1") == token


def test_cache_keys_are_namespaced_by_tenant_and_agent():
    tok_a = _make_jwt(time.time() + 3600)
    tok_b = _make_jwt(time.time() + 3600)
    token_cache.cache_agentic_token("tenant-a", "agent-1", tok_a)
    token_cache.cache_agentic_token("tenant-b", "agent-1", tok_b)

    assert token_cache.get_cached_agentic_token("tenant-a", "agent-1") == tok_a
    assert token_cache.get_cached_agentic_token("tenant-b", "agent-1") == tok_b
    assert token_cache.get_cached_agentic_token("tenant-a", "agent-2") is None


def test_cache_overwrites_existing_token():
    old = _make_jwt(time.time() + 3600)
    new = _make_jwt(time.time() + 3600)
    token_cache.cache_agentic_token("tenant-a", "agent-1", old)
    token_cache.cache_agentic_token("tenant-a", "agent-1", new)
    assert token_cache.get_cached_agentic_token("tenant-a", "agent-1") == new


def test_expired_token_is_evicted_on_read():
    expired = _make_jwt(time.time() - 60)
    token_cache.cache_agentic_token("tenant-a", "agent-1", expired)
    assert token_cache.get_cached_agentic_token("tenant-a", "agent-1") is None
    # Subsequent calls also see the miss because the entry was pruned.
    assert "tenant-a:agent-1" not in token_cache._agentic_token_cache


def test_token_within_skew_window_treated_as_expired():
    # Expires in 10 seconds; default skew is 30 seconds → treat as expired.
    near_expiry = _make_jwt(time.time() + 10)
    token_cache.cache_agentic_token("tenant-a", "agent-1", near_expiry)
    assert token_cache.get_cached_agentic_token("tenant-a", "agent-1") is None


def test_explicit_exp_overrides_jwt_claim():
    # Token claim says expired, but caller passes a future exp_unix.
    expired_claim = _make_jwt(time.time() - 60)
    token_cache.cache_agentic_token(
        "tenant-a", "agent-1", expired_claim, exp_unix=time.time() + 3600
    )
    assert token_cache.get_cached_agentic_token("tenant-a", "agent-1") == expired_claim


def test_opaque_token_uses_fallback_ttl():
    # Non-JWT string: falls back to _FALLBACK_TTL_SECONDS, so a fresh insert
    # is retrievable, but the entry has a real expiry attached.
    token_cache.cache_agentic_token("tenant-a", "agent-1", "opaque-blob")
    assert token_cache.get_cached_agentic_token("tenant-a", "agent-1") == "opaque-blob"
    _, exp = token_cache._agentic_token_cache["tenant-a:agent-1"]
    assert exp > time.time()


def test_cache_evict_drops_entry():
    token = _make_jwt(time.time() + 3600)
    token_cache.cache_agentic_token("tenant-a", "agent-1", token)
    token_cache.cache_evict("tenant-a", "agent-1")
    assert token_cache.get_cached_agentic_token("tenant-a", "agent-1") is None


def test_cache_evict_missing_key_is_noop():
    # Should not raise even when the key was never cached.
    token_cache.cache_evict("tenant-x", "agent-x")

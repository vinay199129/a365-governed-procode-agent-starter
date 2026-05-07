# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.

"""
Token caching utilities for Agent 365 Observability exporter authentication.

Cache entries store (token, exp_unix) tuples. Expiry is read from the JWT's
`exp` claim when the token is cached and pruned on every read so a stale
token can't be returned to the OTel exporter (which would 401 the trace
batch and silently drop spans).
"""

import base64
import json
import logging
import threading
import time

logger = logging.getLogger(__name__)

# How early (in seconds) before the JWT exp claim to consider a token expired.
# Gives the caller a short window to refresh before the wire-side expiry.
_DEFAULT_SKEW_SECONDS = 30

# How long (in seconds) to keep a token if its `exp` claim cannot be parsed.
# Keeps the cache useful for opaque tokens while still capping staleness.
_FALLBACK_TTL_SECONDS = 300

_agentic_token_cache: dict[str, tuple[str, float]] = {}
_lock = threading.Lock()


def _decode_jwt_exp(token: str) -> float | None:
    """Best-effort extraction of the `exp` claim from a JWT.

    Returns None for non-JWT tokens or when the claim is missing/unparseable.
    Never raises — callers fall back to _FALLBACK_TTL_SECONDS.
    """
    try:
        parts = token.split(".")
        if len(parts) < 2:
            return None
        payload_b64 = parts[1]
        # JWT uses URL-safe base64 without padding; restore the padding.
        padding = "=" * (-len(payload_b64) % 4)
        payload_bytes = base64.urlsafe_b64decode(payload_b64 + padding)
        claims = json.loads(payload_bytes)
        exp = claims.get("exp")
        return float(exp) if exp is not None else None
    except (ValueError, TypeError, json.JSONDecodeError):
        return None


def cache_agentic_token(
    tenant_id: str, agent_id: str, token: str, exp_unix: float | None = None
) -> None:
    """Cache the agentic token for use by Agent 365 Observability exporter.

    `exp_unix` is the absolute Unix timestamp at which the token expires. When
    omitted, the JWT `exp` claim is used; if that's missing, the token is
    held for _FALLBACK_TTL_SECONDS so opaque tokens still benefit from
    caching but cannot leak indefinitely.
    """
    if exp_unix is None:
        exp_unix = _decode_jwt_exp(token)
    if exp_unix is None:
        exp_unix = time.time() + _FALLBACK_TTL_SECONDS
    key = f"{tenant_id}:{agent_id}"
    with _lock:
        _agentic_token_cache[key] = (token, exp_unix)
    logger.debug("Cached agentic token for %s (expires at %s)", key, exp_unix)


def get_cached_agentic_token(
    tenant_id: str, agent_id: str, skew_seconds: float = _DEFAULT_SKEW_SECONDS
) -> str | None:
    """Retrieve cached agentic token. Returns None if missing or near-expiry.

    Tokens within `skew_seconds` of their expiry are evicted and treated as a
    cache miss so the caller refreshes before the OBS endpoint sees a 401.
    """
    key = f"{tenant_id}:{agent_id}"
    now = time.time()
    with _lock:
        entry = _agentic_token_cache.get(key)
        if entry is None:
            logger.debug("No cached token found for %s", key)
            return None
        token, exp_unix = entry
        if exp_unix - skew_seconds <= now:
            del _agentic_token_cache[key]
            logger.debug("Evicted expired token for %s", key)
            return None
    logger.debug("Retrieved cached agentic token for %s", key)
    return token


def cache_evict(tenant_id: str, agent_id: str) -> None:
    """Drop a cached token (e.g. after the OBS endpoint rejects it as 401)."""
    key = f"{tenant_id}:{agent_id}"
    with _lock:
        _agentic_token_cache.pop(key, None)


def cache_clear() -> None:
    """Drop every cached token. Primarily for tests and process shutdown."""
    with _lock:
        _agentic_token_cache.clear()

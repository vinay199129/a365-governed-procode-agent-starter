"""Refresh SECRET_BEARER_TOKEN for MCP tool authentication.

Uses MSAL with an on-disk SerializableTokenCache (DPAPI-encrypted on Windows)
so device-code flow only runs when the cache is empty or refresh tokens have
expired.

Fast-path: if the existing SECRET_BEARER_TOKEN in env/.env.playground.user has
more than 5 minutes left, exits without doing anything.
"""

from __future__ import annotations

import base64
import ctypes
import ctypes.wintypes
import json
import os
import sys
import time
from pathlib import Path

import msal

WORKSPACE = Path(__file__).resolve().parents[2]
PLAYGROUND_ENV = WORKSPACE / "env" / ".env.playground"
PLAYGROUND_USER_ENV = WORKSPACE / "env" / ".env.playground.user"
CONFIG_PATH = WORKSPACE / "a365.config.json"
MANIFEST_PATH = WORKSPACE / "ToolingManifest.json"

CACHE_DIR = Path(os.environ["LOCALAPPDATA"]) / "a365-procode-agent" / "msal-cache"


# --- DPAPI helpers (Windows CurrentUser scope) ---

class _DataBlob(ctypes.Structure):
    _fields_ = [("cbData", ctypes.wintypes.DWORD),
                ("pbData", ctypes.POINTER(ctypes.c_byte))]


def _dpapi(func_name: str, data: bytes) -> bytes:
    crypt32 = ctypes.windll.crypt32
    fn = getattr(crypt32, func_name)
    in_blob = _DataBlob(len(data), ctypes.cast(ctypes.c_char_p(data), ctypes.POINTER(ctypes.c_byte)))
    out_blob = _DataBlob()
    if not fn(ctypes.byref(in_blob), None, None, None, None, 0, ctypes.byref(out_blob)):
        raise ctypes.WinError(ctypes.get_last_error())
    try:
        return ctypes.string_at(out_blob.pbData, out_blob.cbData)
    finally:
        ctypes.windll.kernel32.LocalFree(out_blob.pbData)


def dpapi_protect(data: bytes) -> bytes:
    return _dpapi("CryptProtectData", data)


def dpapi_unprotect(data: bytes) -> bytes:
    return _dpapi("CryptUnprotectData", data)


# --- Env file helpers ---

def read_env_value(path: Path, key: str) -> str | None:
    if not path.exists():
        return None
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.lstrip().startswith(f"{key}="):
            return line.split("=", 1)[1].strip()
    return None


def write_env_value(path: Path, key: str, value: str) -> None:
    lines = path.read_text(encoding="utf-8").splitlines() if path.exists() else []
    for i, line in enumerate(lines):
        if line.lstrip().startswith(f"{key}="):
            lines[i] = f"{key}={value}"
            break
    else:
        if lines and lines[-1].strip():
            lines.append("")
        lines.append(f"{key}={value}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


# --- Fast-path: check existing token expiry ---

def existing_token_minutes_remaining() -> int | None:
    token = read_env_value(PLAYGROUND_USER_ENV, "SECRET_BEARER_TOKEN")
    if not token:
        return None
    parts = token.split(".")
    if len(parts) < 2:
        return None
    try:
        payload = parts[1] + "=" * (-len(parts[1]) % 4)
        claims = json.loads(base64.urlsafe_b64decode(payload).decode("utf-8"))
        return int((claims["exp"] - time.time()) / 60)
    except Exception:
        return None


# --- MSAL cache ---

def load_cache(cache_path: Path) -> msal.SerializableTokenCache:
    cache = msal.SerializableTokenCache()
    if cache_path.exists():
        try:
            cache.deserialize(dpapi_unprotect(cache_path.read_bytes()).decode("utf-8"))
        except Exception as exc:
            print(f"  (cache load failed, starting fresh: {exc})", file=sys.stderr)
    return cache


def save_cache(cache: msal.SerializableTokenCache, cache_path: Path) -> None:
    if not cache.has_state_changed:
        return
    cache_path.parent.mkdir(parents=True, exist_ok=True)
    cache_path.write_bytes(dpapi_protect(cache.serialize().encode("utf-8")))


# --- Main ---

def main() -> int:
    remaining = existing_token_minutes_remaining()
    if remaining is not None and remaining > 5:
        print(f"Existing SECRET_BEARER_TOKEN valid for {remaining} more minutes \u2014 skipping refresh.")
        return 0

    config = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    tenant_id = config["tenantId"]
    client_app_id = read_env_value(PLAYGROUND_ENV, "CLIENT_APP_ID")
    if not client_app_id:
        print("CLIENT_APP_ID not found in env/.env.playground", file=sys.stderr)
        return 1

    resource_app_id = manifest["mcpServers"][0]["audience"]
    raw_scopes = sorted({s["scope"] for s in manifest["mcpServers"]})
    scopes = [f"{resource_app_id}/{s}" for s in raw_scopes]

    print("=" * 60)
    print(" Bearer Token Refresh (MSAL Python, device code flow)")
    print("=" * 60)
    print(f"  Tenant:     {tenant_id}")
    print(f"  Client App: {client_app_id}")
    print(f"  Resource:   {resource_app_id}")
    print(f"  Scopes:     {', '.join(raw_scopes)}")
    print()

    cache_path = CACHE_DIR / f"{client_app_id}.bin"
    cache = load_cache(cache_path)

    app = msal.PublicClientApplication(
        client_app_id,
        authority=f"https://login.microsoftonline.com/{tenant_id}",
        token_cache=cache,
    )

    result = None
    accounts = app.get_accounts()
    if accounts:
        print("Attempting silent token acquisition (cached)...")
        result = app.acquire_token_silent(scopes, account=accounts[0])
        if result and "access_token" in result:
            print("Token acquired from cache.")

    if not result or "access_token" not in result:
        print("Using device code flow for authentication...\n")
        flow = app.initiate_device_flow(scopes=scopes)
        if "user_code" not in flow:
            print(f"Device flow init failed: {flow}", file=sys.stderr)
            return 1
        print("-" * 60)
        print(flow["message"])
        print("-" * 60)
        print()
        result = app.acquire_token_by_device_flow(flow)

    save_cache(cache, cache_path)

    if "access_token" not in result:
        print(f"Failed to acquire token: {result.get('error_description', result)}", file=sys.stderr)
        return 1

    token = result["access_token"]
    print(f"\nToken acquired successfully (length: {len(token)} chars)")
    write_env_value(PLAYGROUND_USER_ENV, "SECRET_BEARER_TOKEN", token)
    print(f"SECRET_BEARER_TOKEN updated in {PLAYGROUND_USER_ENV.relative_to(WORKSPACE)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

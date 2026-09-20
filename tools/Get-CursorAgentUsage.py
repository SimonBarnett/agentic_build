#!/usr/bin/env python3
"""Read Grok Bot / Cursor-agent weekly usage. Prints JSON only (no tokens)."""
from __future__ import annotations

import base64
import ctypes
import json
import os
import sys
import urllib.error
import urllib.request
from ctypes import wintypes
from pathlib import Path

APP = Path(os.environ.get("APPDATA", "")) / "Grok Bot"


class DATA_BLOB(ctypes.Structure):
    _fields_ = [("cbData", wintypes.DWORD), ("pbData", ctypes.POINTER(ctypes.c_char))]


def _dpapi_unprotect(raw: bytes) -> bytes:
    blob_in = DATA_BLOB(len(raw), ctypes.cast(raw, ctypes.POINTER(ctypes.c_char)))
    blob_out = DATA_BLOB()
    crypt32 = ctypes.windll.crypt32
    kernel32 = ctypes.windll.kernel32
    if not crypt32.CryptUnprotectData(
        ctypes.byref(blob_in), None, None, None, None, 0, ctypes.byref(blob_out)
    ):
        raise OSError("CryptUnprotectData failed")
    try:
        return ctypes.string_at(blob_out.pbData, blob_out.cbData)
    finally:
        kernel32.LocalFree(blob_out.pbData)


def _chrome_key(local_state: Path) -> bytes:
    wrap = json.loads(local_state.read_text(encoding="utf-8"))
    enc = base64.b64decode(wrap["os_crypt"]["encrypted_key"])
    if enc.startswith(b"DPAPI"):
        enc = enc[5:]
    return _dpapi_unprotect(enc)


def _decrypt_v10(key: bytes, blob_b64: str) -> str:
    raw = base64.b64decode(blob_b64)
    if raw.startswith(b"v10"):
        raw = raw[3:]
    nonce, ct_tag = raw[:12], raw[12:]
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM

    pt = AESGCM(key).decrypt(nonce, ct_tag, None)
    return pt.decode("utf-8")


def _access_token(key: bytes) -> str | None:
    secrets = json.loads((APP / "sand-secrets.json").read_text(encoding="utf-8"))
    accounts = json.loads(secrets.get("cursor-accounts") or "{}")
    active = accounts.get("active")
    rec = (accounts.get("accounts") or {}).get(active) or {}
    blob = rec.get("cursor-access-token")
    if not blob:
        return None
    return _decrypt_v10(key, blob)


def _fetch_json(token: str, path: str) -> dict:
    url = "https://api2.cursor.sh/" + path
    req = urllib.request.Request(
        url,
        data=b"{}",
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "Connect-Protocol-Version": "1",
        },
    )
    with urllib.request.urlopen(req, timeout=4) as resp:
        return json.loads(resp.read().decode("utf-8"))


def _fetch_usage(token: str) -> dict:
    # Grok Bot "Weekly usage 98%" is Sand usagePercent (USED), not plan remaining.
    return _fetch_json(token, "aiserver.v1.DashboardService/GetSandUsageStatus")


def main() -> int:
    try:
        key = _chrome_key(APP / "Local State")
        token = _access_token(key)
        if not token:
            print("{}", end="")
            return 1
        body = _fetch_usage(token)
        used = body.get("usagePercent")
        if used is None:
            used = body.get("percentUsed")
        if used is None:
            print(json.dumps({"ok": False, "error": "no usagePercent"}))
            return 1
        used_f = float(used)
        if 0.0 <= used_f <= 1.0:
            used_f = used_f * 100.0
        remain = int(round(100.0 - used_f))
        if remain < 0:
            remain = 0
        if remain > 100:
            remain = 100
        print(
            json.dumps(
                {
                    "ok": True,
                    "used_pct": int(round(used_f if used_f is not None else (100 - remain))),
                    "remaining_pct": remain,
                    "source": "cursor-agent",
                    "kind": "weekly",
                }
            )
        )
        return 0
    except Exception as e:
        print(json.dumps({"ok": False, "error": type(e).__name__}))
        return 1


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Read Cursor Spending (Cursor Models) + Sand + on-demand overage. Prints JSON only."""
from __future__ import annotations

import base64
import ctypes
import json
import os
import sys
import urllib.error
import urllib.request
from ctypes import wintypes
from datetime import datetime, timezone
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
    with urllib.request.urlopen(req, timeout=6) as resp:
        return json.loads(resp.read().decode("utf-8"))


def _usd_to_gbp(usd: float) -> float | None:
    """Convert USD to GBP. Prefer open.er-api.com; fallback jsDelivr currency-api."""
    endpoints = (
        ("https://open.er-api.com/v6/latest/USD", lambda b: float((b.get("rates") or {}).get("GBP") or 0)),
        (
            "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.json",
            lambda b: float(((b.get("usd") or {}).get("gbp") or 0)),
        ),
    )
    for url, pick in endpoints:
        try:
            req = urllib.request.Request(url, method="GET", headers={"Accept": "application/json"})
            with urllib.request.urlopen(req, timeout=4) as resp:
                body = json.loads(resp.read().decode("utf-8"))
            rate = pick(body)
            if rate and rate > 0:
                return round(usd * rate, 2)
        except Exception:
            continue
    return None


def _on_demand_usd_cents(period: dict | None) -> tuple[int | None, str | None]:
    if not period:
        return None, None
    slu = period.get("spendLimitUsage") or {}
    for key in ("individualUsed", "totalSpend"):
        v = slu.get(key)
        if v is None or v == "":
            continue
        try:
            cents = int(round(float(v)))
        except (TypeError, ValueError):
            continue
        if cents < 0:
            continue
        return cents, f"period.spendLimitUsage.{key}"
    pu = period.get("planUsage") or {}
    try:
        total = float(pu.get("totalSpend"))
        included = float(pu.get("includedSpend"))
        over = int(round(total - included))
        if over > 0:
            return over, "period.planUsage.totalSpend-includedSpend"
    except (TypeError, ValueError):
        pass
    return None, None


def _parse_used_remain(raw) -> tuple[int | None, int | None]:
    if raw is None or raw == "":
        return None, None
    try:
        used_f = float(raw)
    except (TypeError, ValueError):
        return None, None
    if 0.0 <= used_f <= 1.0:
        used_f = used_f * 100.0
    used_i = int(round(used_f))
    remain = int(round(100.0 - used_f))
    return used_i, remain


def _period_end_iso(period: dict | None) -> str | None:
    if not period:
        return None
    for key in ("billingCycleEnd", "periodEnd", "endDate", "end"):
        v = period.get(key)
        if v is None or v == "":
            continue
        try:
            ms = int(float(v))
            if ms > 10_000_000_000:
                return datetime.fromtimestamp(ms / 1000.0, tz=timezone.utc).strftime(
                    "%Y-%m-%dT%H:%M:%SZ"
                )
        except (TypeError, ValueError):
            pass
        return str(v)
    return None


def main() -> int:
    try:
        key = _chrome_key(APP / "Local State")
        token = _access_token(key)
        if not token:
            print("{}", end="")
            return 1
        sand = _fetch_json(token, "aiserver.v1.DashboardService/GetSandUsageStatus")
        try:
            period = _fetch_json(token, "aiserver.v1.DashboardService/GetCurrentPeriodUsage")
        except Exception:
            period = None

        # Spending "Cursor Models" (includes Cursor Grok + Composer).
        cursor_used = None
        cursor_remain = None
        if period:
            pu = period.get("planUsage") or {}
            auto = pu.get("autoPercentUsed")
            if auto is None or auto == "":
                auto = period.get("autoPercentUsed")
            cursor_used, cursor_remain = _parse_used_remain(auto)

        # Grok Bot Sand — separate from Cursor Models fuel.
        sand_raw = sand.get("usagePercent")
        if sand_raw is None:
            sand_raw = sand.get("percentUsed")
        sand_used, sand_remain = _parse_used_remain(sand_raw)

        cents, cents_src = _on_demand_usd_cents(period)
        overage_gbp = None
        overage_usd = None
        overage_source = None
        fx_rate = None
        if cents is not None:
            overage_usd = round(cents / 100.0, 2)
            overage_source = cents_src
            gbp = _usd_to_gbp(overage_usd)
            if gbp is not None:
                overage_gbp = gbp
                if overage_usd > 0:
                    fx_rate = round(overage_gbp / overage_usd, 6)

        out: dict = {
            "ok": True,
            "source": "cursor-agent",
            "kind": "weekly",
        }
        if cursor_used is not None:
            out["used_pct"] = cursor_used
            out["remaining_pct"] = cursor_remain
            out["cursor_models_source"] = "GetCurrentPeriodUsage.planUsage.autoPercentUsed"
        if sand_used is not None:
            out["sand_used_pct"] = sand_used
            out["sand_remaining_pct"] = sand_remain
            if sand_remain is not None and sand_remain <= 0:
                out["sand_exhausted"] = True
        if overage_usd is not None:
            out["overage_usd"] = overage_usd
            out["on_demand_used_cents"] = cents
        if overage_gbp is not None:
            out["overage_gbp"] = overage_gbp
        if overage_source:
            out["overage_source"] = overage_source
        if fx_rate is not None:
            out["usd_gbp_rate"] = fx_rate

        period_end = _period_end_iso(period)
        if period_end:
            out["period_end"] = period_end

        if cursor_used is None and sand_used is None and overage_gbp is None and overage_usd is None:
            print(json.dumps({"ok": False, "error": "no cursor or sand usage"}))
            return 1
        print(json.dumps(out))
        return 0
    except Exception as e:
        print(json.dumps({"ok": False, "error": type(e).__name__}))
        return 1


if __name__ == "__main__":
    sys.exit(main())

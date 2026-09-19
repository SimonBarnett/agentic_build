# Talk to named Grok Bots (Bob/Haitch/Merc/...) via aiserver.v1.GrokBotService.
# Prints JSON only. Never prints tokens or cookie values.
from __future__ import annotations

import argparse
import base64
import ctypes
import ctypes.wintypes as wt
import glob
import json
import os
import sys
import time
import uuid
import urllib.error
import urllib.request

CRYPTPROTECT_UI_FORBIDDEN = 0x01
API_HOST = "https://api2.cursor.sh/"
GROK_BOT_SERVICE = "aiserver.v1.GrokBotService"
API_BASE = API_HOST + GROK_BOT_SERVICE
_REDACT_KEYS = ("token", "url", "credential", "authorization", "secret", "cookie", "password")


class DATA_BLOB(ctypes.Structure):
    _fields_ = [("cbData", wt.DWORD), ("pbData", ctypes.POINTER(ctypes.c_byte))]


def _dpapi_decrypt(blob: bytes) -> bytes:
    inb = DATA_BLOB(len(blob), (ctypes.c_byte * len(blob)).from_buffer_copy(blob))
    out = DATA_BLOB()
    if not ctypes.windll.crypt32.CryptUnprotectData(
        ctypes.byref(inb), None, None, None, None, CRYPTPROTECT_UI_FORBIDDEN, ctypes.byref(out)
    ):
        raise OSError("CryptUnprotectData failed")
    try:
        return ctypes.string_at(out.pbData, out.cbData)
    finally:
        ctypes.windll.kernel32.LocalFree(out.pbData)


def _chrome_key(local_state: str) -> bytes:
    ls = json.load(open(local_state, encoding="utf-8"))
    enc = base64.b64decode(ls["os_crypt"]["encrypted_key"])
    if enc.startswith(b"DPAPI"):
        enc = enc[5:]
    return _dpapi_decrypt(enc)


def _aes_gcm_decrypt(key: bytes, nonce: bytes, ct: bytes, tag: bytes) -> bytes:
    try:
        from cryptography.hazmat.primitives.ciphers.aead import AESGCM

        return AESGCM(key).decrypt(nonce, ct + tag, None)
    except ImportError:
        pass
    bcrypt = ctypes.windll.bcrypt
    bcrypt.BCryptOpenAlgorithmProvider.restype = ctypes.c_long
    bcrypt.BCryptSetProperty.restype = ctypes.c_long
    bcrypt.BCryptGenerateSymmetricKey.restype = ctypes.c_long
    bcrypt.BCryptDecrypt.restype = ctypes.c_long
    alg = ctypes.c_void_p()
    st = bcrypt.BCryptOpenAlgorithmProvider(ctypes.byref(alg), "AES", None, 0)
    if st:
        raise OSError("BCryptOpenAlgorithmProvider %s" % st)
    try:
        chaining = ctypes.create_unicode_buffer("ChainingModeGCM")
        st = bcrypt.BCryptSetProperty(
            alg, "ChainingMode", ctypes.cast(chaining, ctypes.c_void_p), ctypes.sizeof(chaining), 0
        )
        if st:
            raise OSError("BCryptSetProperty %s" % st)
        kh = ctypes.c_void_p()
        key_buf = ctypes.create_string_buffer(key, len(key))
        st = bcrypt.BCryptGenerateSymmetricKey(alg, ctypes.byref(kh), None, 0, key_buf, len(key), 0)
        if st:
            raise OSError("BCryptGenerateSymmetricKey %s" % st)
        try:

            class INFO(ctypes.Structure):
                _fields_ = [
                    ("cbSize", ctypes.c_ulong),
                    ("dwInfoVersion", ctypes.c_ulong),
                    ("pbNonce", ctypes.c_void_p),
                    ("cbNonce", ctypes.c_ulong),
                    ("pbAuthData", ctypes.c_void_p),
                    ("cbAuthData", ctypes.c_ulong),
                    ("pbTag", ctypes.c_void_p),
                    ("cbTag", ctypes.c_ulong),
                    ("pbMacContext", ctypes.c_void_p),
                    ("cbMacContext", ctypes.c_ulong),
                    ("cbAAD", ctypes.c_ulong),
                    ("cbData", ctypes.c_ulonglong),
                    ("dwFlags", ctypes.c_ulong),
                ]

            info = INFO()
            info.cbSize = ctypes.sizeof(info)
            info.dwInfoVersion = 1
            nonce_buf = ctypes.create_string_buffer(nonce, len(nonce))
            tag_buf = ctypes.create_string_buffer(tag, len(tag))
            info.pbNonce = ctypes.cast(nonce_buf, ctypes.c_void_p)
            info.cbNonce = len(nonce)
            info.pbTag = ctypes.cast(tag_buf, ctypes.c_void_p)
            info.cbTag = len(tag)
            ct_buf = ctypes.create_string_buffer(ct, len(ct))
            out = ctypes.create_string_buffer(len(ct))
            out_len = ctypes.c_ulong()
            st = bcrypt.BCryptDecrypt(
                kh, ct_buf, len(ct), ctypes.byref(info), None, 0, out, len(ct), ctypes.byref(out_len), 0
            )
            if st:
                raise OSError("BCryptDecrypt %s" % hex(st))
            return out.raw[: out_len.value]
        finally:
            bcrypt.BCryptDestroyKey(kh)
    finally:
        bcrypt.BCryptCloseAlgorithmProvider(alg, 0)


def _chrome_decrypt(token_b64: str, key: bytes) -> str:
    raw = base64.b64decode(token_b64)
    if not (raw.startswith(b"v10") or raw.startswith(b"v11")):
        raise ValueError("unexpected token prefix")
    data = raw[3:]
    nonce, ct_tag = data[:12], data[12:]
    ct, tag = ct_tag[:-16], ct_tag[-16:]
    return _aes_gcm_decrypt(key, nonce, ct, tag).decode("utf-8")


def _iet(buf: bytearray) -> bytearray:
    t = 165
    for r in range(len(buf)):
        buf[r] = ((buf[r] ^ t) + (r % 256)) & 255
        t = buf[r]
    return buf


def _checksum(machine_id: str) -> str:
    t = int(time.time() * 1000) // 1_000_000
    r = bytearray(
        [(t >> 40) & 255, (t >> 32) & 255, (t >> 24) & 255, (t >> 16) & 255, (t >> 8) & 255, t & 255]
    )
    return base64.urlsafe_b64encode(bytes(_iet(r))).decode("ascii").rstrip("=") + machine_id


def grok_bot_homes() -> list[str]:
    homes = []
    env = os.environ.get("BOB_GROK_BOT_HOME")
    if env:
        homes.append(env)
    appdata = os.environ.get("APPDATA")
    if appdata:
        homes.append(os.path.join(appdata, "Grok Bot"))
    user = os.environ.get("USERPROFILE")
    if user:
        homes.append(os.path.join(user, "AppData", "Roaming", "Grok Bot"))
    homes.append(r"D:\Users\Administrator\AppData\Roaming\Grok Bot")
    out = []
    seen = set()
    for h in homes:
        p = os.path.abspath(h)
        if p.lower() in seen:
            continue
        seen.add(p.lower())
        out.append(p)
    return out


def find_home() -> str | None:
    for h in grok_bot_homes():
        if os.path.isfile(os.path.join(h, "sand-secrets.json")):
            return h
    return None


def load_roster(home: str) -> list[dict]:
    persist = os.path.join(home, "sand-client-persistence")
    for path in glob.glob(os.path.join(persist, "*.blob")):
        try:
            data = json.load(open(path, encoding="utf-8"))
        except Exception:
            continue
        val = data.get("value") if isinstance(data, dict) else None
        rows = val.get("rows") if isinstance(val, dict) else None
        if rows:
            return rows
    return []


def resolve_agent(home: str, name: str) -> dict:
    want = name.strip().lower()
    if want.startswith("agent:"):
        want = want.split(":", 1)[1]
    for row in load_roster(home):
        n = (row.get("name") or "").strip()
        if n.lower() == want or (row.get("id") or "").lower() == want:
            return row
    raise SystemExit(json.dumps({"ok": False, "error": "agent_not_found", "agent": name}))


def desktop_status(home: str) -> dict:
    path = os.path.join(home, "desktop-status.json")
    if not os.path.isfile(path):
        return {}
    try:
        return json.load(open(path, encoding="utf-8"))
    except Exception:
        return {}


def load_auth(home: str) -> tuple[str, str]:
    secrets = json.load(open(os.path.join(home, "sand-secrets.json"), encoding="utf-8"))
    accounts = json.loads(secrets["cursor-accounts"])
    acc = accounts["accounts"][accounts["active"]]
    key = _chrome_key(os.path.join(home, "Local State"))
    access = _chrome_decrypt(acc["cursor-access-token"], key)
    machine = _chrome_decrypt(secrets["cursor-machine-id"], key)
    return access, machine


def _redact(obj):
    if isinstance(obj, dict):
        out = {}
        for k, v in obj.items():
            kl = str(k).lower()
            if any(s in kl for s in _REDACT_KEYS):
                out[k] = "<redacted>"
            else:
                out[k] = _redact(v)
        return out
    if isinstance(obj, list):
        return [_redact(x) for x in obj]
    return obj


def grokbot_post(
    access: str,
    machine: str,
    method: str,
    payload: dict,
    service: str | None = None,
) -> tuple[int, dict | str]:
    body = json.dumps(payload).encode("utf-8")
    headers = {
        "Content-Type": "application/json",
        "Connect-Protocol-Version": "1",
        "Authorization": "Bearer " + access,
        "x-cursor-client-type": "sand",
        "x-cursor-client-version": "0.56.1",
        "x-cursor-client-os": "win32",
        "x-cursor-checksum": _checksum(machine),
        "x-ghost-mode": "true",
        "User-Agent": "BobBridge/0.2",
    }
    svc = (service or GROK_BOT_SERVICE).strip().strip("/")
    req = urllib.request.Request(API_HOST + svc + "/" + method, data=body, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
            try:
                return resp.status, json.loads(raw) if raw else {}
            except json.JSONDecodeError:
                return resp.status, raw
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", errors="replace")
        try:
            parsed = json.loads(raw) if raw else {}
        except json.JSONDecodeError:
            parsed = raw
        return e.code, parsed


def emit(obj: dict, ok: bool = True) -> None:
    obj.setdefault("ok", ok)
    sys.stdout.write(json.dumps(obj, ensure_ascii=True) + "\n")


def last_text(row: dict) -> str:
    last = row.get("lastEntry") or {}
    return last.get("text") or last.get("kind") or ""


def cmd_list(home: str) -> None:
    status = desktop_status(home)
    agents = []
    for row in load_roster(home):
        agents.append(
            {
                "id": row.get("id"),
                "name": row.get("name"),
                "title": row.get("title"),
                "description": row.get("description"),
                "lastActivityAt": row.get("lastActivityAt"),
                "unreadCount": row.get("unreadCount") or 0,
                "last": last_text(row)[:400],
            }
        )
    emit(
        {
            "home": home,
            "signedIn": bool(status.get("signedIn")),
            "appVersion": status.get("appVersion"),
            "agents": agents,
        }
    )


def cmd_send(home: str, agent: str, text: str, wait: bool, timeout: int) -> None:
    row = resolve_agent(home, agent)
    access, machine = load_auth(home)
    sent_at = int(time.time() * 1000)
    nonce = str(uuid.uuid4())
    code, body = grokbot_post(
        access,
        machine,
        "SendGrokBotUserMessage",
        {
            "agentId": row["id"],
            "messageId": nonce,
            "text": text,
            "sentAtMs": str(sent_at),
            "machineId": machine,
        },
    )
    result = {
        "agent": row.get("name"),
        "agentId": row.get("id"),
        "messageId": nonce,
        "sentAtMs": sent_at,
        "http": code,
        "delivery": body.get("delivery") if isinstance(body, dict) else None,
        "dispatched": body.get("dispatched") if isinstance(body, dict) else None,
        "api": body if not isinstance(body, dict) else {k: body[k] for k in body if k != "authorization"},
    }
    if code != 200 or not (isinstance(body, dict) and body.get("dispatched")):
        emit({**result, "error": "send_refused"}, ok=False)
        raise SystemExit(1)
    if not wait:
        emit(result)
        return
    waited = cmd_wait_inner(home, row["id"], sent_at, timeout, text)
    emit({**result, **waited}, ok=bool(waited.get("ok", True)))
    if not waited.get("ok", True):
        raise SystemExit(2)


def cmd_wait_inner(home: str, agent_id: str, after_ms: int, timeout: int, prompt: str) -> dict:
    deadline = time.time() + timeout
    prompt_norm = (prompt or "").strip()
    last_seen = None
    while time.time() < deadline:
        row = None
        for r in load_roster(home):
            if r.get("id") == agent_id:
                row = r
                break
        if row:
            activity = int(row.get("lastActivityAt") or 0)
            text = last_text(row).strip()
            last_seen = text
            if activity > after_ms and text and text != prompt_norm:
                return {
                    "ok": True,
                    "text": last_text(row),
                    "lastActivityAt": activity,
                    "waitedMs": int(time.time() * 1000) - after_ms,
                }
        time.sleep(2)
    return {
        "ok": False,
        "error": "timeout",
        "last": last_seen,
        "waitedMs": int(time.time() * 1000) - after_ms,
    }


def cmd_interrupt(home: str, agent: str) -> None:
    row = resolve_agent(home, agent)
    access, machine = load_auth(home)
    code, body = grokbot_post(
        access,
        machine,
        "InterruptGrokBotAgentRun",
        {"agentId": row["id"], "reason": "user_interrupt"},
    )
    emit(
        {
            "agent": row.get("name"),
            "agentId": row.get("id"),
            "http": code,
            "api": body,
        },
        ok=(code == 200),
    )
    if code != 200:
        raise SystemExit(1)


def cmd_post(home: str, method: str, payload: dict, service: str, agent: str) -> None:
    body = dict(payload or {})
    if agent:
        row = resolve_agent(home, agent)
        body.setdefault("agentId", row["id"])
    access, machine = load_auth(home)
    code, raw = grokbot_post(access, machine, method, body, service=service or GROK_BOT_SERVICE)
    emit(
        {
            "method": method,
            "service": service or GROK_BOT_SERVICE,
            "http": code,
            "api": _redact(raw) if isinstance(raw, (dict, list)) else raw,
        },
        ok=(code == 200),
    )
    if code != 200:
        raise SystemExit(1)


def cmd_health(home: str) -> None:
    status = desktop_status(home)
    emit(
        {
            "home": home,
            "signedIn": bool(status.get("signedIn")),
            "appVersion": status.get("appVersion"),
            "pid": status.get("pid"),
            "agentCount": len(load_roster(home)),
        }
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Grok Bot agent API for BobBridge")
    parser.add_argument("action", choices=["list", "send", "interrupt", "health", "post"])
    parser.add_argument("--agent", default="")
    parser.add_argument("--text", default="")
    parser.add_argument("--text-file", default="")
    parser.add_argument("--wait", action="store_true")
    parser.add_argument("--timeout", type=int, default=180)
    parser.add_argument("--method", default="")
    parser.add_argument("--service", default=GROK_BOT_SERVICE)
    parser.add_argument("--json", default="")
    parser.add_argument("--json-file", default="")
    args = parser.parse_args()
    if args.text_file:
        args.text = open(args.text_file, encoding="utf-8").read()
    home = find_home()
    if not home:
        emit({"error": "grokbot_home_missing"}, ok=False)
        raise SystemExit(1)
    if args.action == "list":
        cmd_list(home)
    elif args.action == "health":
        cmd_health(home)
    elif args.action == "send":
        if not args.agent or not args.text:
            emit({"error": "agent_and_text_required"}, ok=False)
            raise SystemExit(2)
        cmd_send(home, args.agent, args.text, args.wait, args.timeout)
    elif args.action == "interrupt":
        if not args.agent:
            emit({"error": "agent_required"}, ok=False)
            raise SystemExit(2)
        cmd_interrupt(home, args.agent)
    elif args.action == "post":
        if not args.method:
            emit({"error": "method_required"}, ok=False)
            raise SystemExit(2)
        payload = {}
        raw_json = args.json
        if args.json_file:
            raw_json = open(args.json_file, encoding="utf-8").read()
        if raw_json.strip():
            payload = json.loads(raw_json)
        if not isinstance(payload, dict):
            emit({"error": "json_object_required"}, ok=False)
            raise SystemExit(2)
        cmd_post(home, args.method, payload, args.service, args.agent)


if __name__ == "__main__":
    main()

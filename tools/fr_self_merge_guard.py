#!/usr/bin/env python3
"""FR #343: flag PRs self-merged by the author within N minutes of opening.

Report-only / CI gate. Does not merge or unmerge. Exit 2 = policy flag.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone
from typing import Any


DEFAULT_MINUTES = 30


def parse_gh_time(s: str) -> datetime | None:
    if not s:
        return None
    s = s.strip().replace("Z", "+00:00")
    try:
        return datetime.fromisoformat(s)
    except ValueError:
        return None


def analyze_pr(
    *,
    author_login: str,
    merged_by_login: str | None,
    created_at: str,
    merged_at: str | None,
    state: str,
    minutes: float = DEFAULT_MINUTES,
) -> dict[str, Any]:
    """Pure verdict from PR fields (no network)."""
    out: dict[str, Any] = {
        "ok": True,
        "flag": False,
        "reason": "",
        "author": author_login or "",
        "merged_by": merged_by_login or "",
        "minutes_open_to_merge": None,
        "threshold_minutes": float(minutes),
        "state": state or "",
        "mrb_pending_announce": "",
    }
    if (state or "").upper() != "MERGED" and not merged_at:
        out["reason"] = "not_merged"
        return out
    if not merged_by_login:
        out["reason"] = "merged_but_no_merged_by"
        return out
    a = (author_login or "").lower()
    m = (merged_by_login or "").lower()
    # bots: still flag if same identity self-merged instantly
    created = parse_gh_time(created_at)
    merged = parse_gh_time(merged_at or "")
    if created and merged:
        delta_m = (merged - created).total_seconds() / 60.0
        out["minutes_open_to_merge"] = round(delta_m, 3)
    else:
        delta_m = None
    if a and m and a == m:
        if delta_m is None or delta_m <= float(minutes):
            out["ok"] = False
            out["flag"] = True
            out["reason"] = "self_merge_within_threshold"
            out["mrb_pending_announce"] = (
                f"MRB-pending: self-merge flag author={author_login} "
                f"merged_in={out['minutes_open_to_merge']}m threshold={minutes}m"
            )
            return out
        out["reason"] = "self_merge_but_outside_threshold"
        return out
    out["reason"] = "merged_by_other"
    return out


def fetch_pr(owner_repo: str, pr: int) -> dict[str, Any]:
    cmd = [
        "gh",
        "pr",
        "view",
        str(pr),
        "--repo",
        owner_repo,
        "--json",
        "author,mergedBy,mergedAt,createdAt,state,url,number,title",
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr or proc.stdout or "gh pr view failed")
    return json.loads(proc.stdout)


def guard_from_gh(owner_repo: str, pr: int, minutes: float) -> dict[str, Any]:
    data = fetch_pr(owner_repo, pr)
    author = ""
    if isinstance(data.get("author"), dict):
        author = str(data["author"].get("login") or "")
    merged_by = None
    if isinstance(data.get("mergedBy"), dict):
        merged_by = str(data["mergedBy"].get("login") or "") or None
    verdict = analyze_pr(
        author_login=author,
        merged_by_login=merged_by,
        created_at=str(data.get("createdAt") or ""),
        merged_at=str(data.get("mergedAt") or "") or None,
        state=str(data.get("state") or ""),
        minutes=minutes,
    )
    verdict["repo"] = owner_repo
    verdict["pr"] = int(pr)
    verdict["url"] = data.get("url")
    verdict["title"] = data.get("title")
    return verdict


def self_test() -> None:
    # author merges in 2 minutes → flag
    v = analyze_pr(
        author_login="alice",
        merged_by_login="alice",
        created_at="2026-09-25T12:00:00Z",
        merged_at="2026-09-25T12:02:00Z",
        state="MERGED",
        minutes=30,
    )
    assert v["flag"] is True and v["ok"] is False, v
    # other merger → ok
    v2 = analyze_pr(
        author_login="alice",
        merged_by_login="bob",
        created_at="2026-09-25T12:00:00Z",
        merged_at="2026-09-25T12:02:00Z",
        state="MERGED",
        minutes=30,
    )
    assert v2["flag"] is False and v2["ok"] is True, v2
    # self merge after long delay → not flagged by time gate
    v3 = analyze_pr(
        author_login="alice",
        merged_by_login="alice",
        created_at="2026-09-25T12:00:00Z",
        merged_at="2026-09-25T14:00:00Z",
        state="MERGED",
        minutes=30,
    )
    assert v3["flag"] is False and v3["reason"] == "self_merge_but_outside_threshold", v3
    # open PR
    v4 = analyze_pr(
        author_login="alice",
        merged_by_login=None,
        created_at="2026-09-25T12:00:00Z",
        merged_at=None,
        state="OPEN",
        minutes=30,
    )
    assert v4["flag"] is False and v4["reason"] == "not_merged", v4
    print("self-test ok")


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="FR #343 self-merge-too-fast guard")
    p.add_argument("--repo", default="", help="owner/repo")
    p.add_argument("--pr", type=int, default=0)
    p.add_argument("--minutes", type=float, default=DEFAULT_MINUTES)
    p.add_argument("--json", action="store_true")
    p.add_argument("--self-test", action="store_true")
    p.add_argument(
        "--fixture",
        default="",
        help="JSON file with author/mergedBy/createdAt/mergedAt/state (offline)",
    )
    args = p.parse_args(argv)
    if args.self_test:
        self_test()
        return 0
    if args.fixture:
        data = json.loads(Path_read(args.fixture))
        author = data.get("author") or {}
        if isinstance(author, dict):
            author_login = str(author.get("login") or "")
        else:
            author_login = str(author)
        mb = data.get("mergedBy")
        merged_by = str(mb.get("login") or "") if isinstance(mb, dict) else (str(mb) if mb else None)
        verdict = analyze_pr(
            author_login=author_login,
            merged_by_login=merged_by or None,
            created_at=str(data.get("createdAt") or ""),
            merged_at=str(data.get("mergedAt") or "") or None,
            state=str(data.get("state") or ""),
            minutes=args.minutes,
        )
    elif args.repo and args.pr:
        verdict = guard_from_gh(args.repo, args.pr, args.minutes)
    else:
        p.error("need --self-test or --fixture or --repo and --pr")
        return 2
    if args.json:
        print(json.dumps(verdict, indent=2))
    else:
        print(verdict.get("reason"), "flag=" + str(verdict.get("flag")))
        if verdict.get("mrb_pending_announce"):
            print(verdict["mrb_pending_announce"])
    return 2 if verdict.get("flag") else 0


def Path_read(path: str) -> str:
    from pathlib import Path

    return Path(path).read_text(encoding="utf-8-sig")


if __name__ == "__main__":
    raise SystemExit(main())

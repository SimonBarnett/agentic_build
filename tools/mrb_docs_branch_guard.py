#!/usr/bin/env python3
"""FR #348: flag feature PRs that received MRB docs commits on the reviewed branch.

MRB must never push to the PR under review. Docs go in a separate
``docs/mrb-<n>-...`` PR. This guard flags when:
  - any commit message on the PR starts with ``docs(MRB`` (case-insensitive), or
  - after ``mrb_started_at`` (optional), a commit author login differs from the
    PR author (reviewer pushed onto the feature branch).

Report-only. Exit 2 = policy flag. Exit 0 = ok / not applicable.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from typing import Any

DOCS_MRB_RE = re.compile(r"^docs\s*\(\s*mrb\b", re.IGNORECASE)


def parse_gh_time(s: str) -> datetime | None:
    if not s:
        return None
    s = s.strip().replace("Z", "+00:00")
    try:
        return datetime.fromisoformat(s)
    except ValueError:
        return None


def analyze_commits(
    *,
    pr_author_login: str,
    commits: list[dict[str, Any]],
    mrb_started_at: str | None = None,
) -> dict[str, Any]:
    """Pure verdict from commit list (no network).

    Each commit dict may include: messageHeadline/message, authoredDate,
    authors (list of {login,name,email}) or authorLogin.
    """
    out: dict[str, Any] = {
        "ok": True,
        "flag": False,
        "reason": "",
        "pr_author": pr_author_login or "",
        "docs_mrb_commits": [],
        "foreign_after_mrb_start": [],
        "mrb_pending_announce": "",
    }
    author = (pr_author_login or "").lower()
    started = parse_gh_time(mrb_started_at or "")
    docs_hits: list[str] = []
    foreign: list[str] = []

    for c in commits or []:
        msg = str(c.get("messageHeadline") or c.get("message") or c.get("oid") or "")
        oid = str(c.get("oid") or "")[:12]
        if DOCS_MRB_RE.search(msg.strip()):
            docs_hits.append(f"{oid}:{msg.strip()[:80]}")
        logins: list[str] = []
        if isinstance(c.get("authors"), list):
            for a in c["authors"]:
                if isinstance(a, dict) and a.get("login"):
                    logins.append(str(a["login"]).lower())
        if c.get("authorLogin"):
            logins.append(str(c["authorLogin"]).lower())
        logins = [x for x in logins if x]
        if not logins or not author or not started:
            continue
        authored = parse_gh_time(str(c.get("authoredDate") or ""))
        if authored and authored >= started:
            if any(l != author for l in logins):
                foreign.append(f"{oid}:{','.join(logins)}:{msg.strip()[:60]}")

    out["docs_mrb_commits"] = docs_hits
    out["foreign_after_mrb_start"] = foreign
    if docs_hits:
        out["ok"] = False
        out["flag"] = True
        out["reason"] = "docs_mrb_commit_on_feature_branch"
        out["mrb_pending_announce"] = (
            "MRB-pending: docs(MRB commit landed on feature PR branch; "
            "use separate docs/mrb-<n> PR (FR #348)"
        )
        return out
    if foreign:
        out["ok"] = False
        out["flag"] = True
        out["reason"] = "foreign_commit_after_mrb_start"
        out["mrb_pending_announce"] = (
            "MRB-pending: non-author commit on feature branch after MRB start "
            "(FR #348 — do not push to the PR under review)"
        )
        return out
    out["reason"] = "clean"
    return out


def fetch_pr_commits(owner_repo: str, pr: int) -> dict[str, Any]:
    cmd = [
        "gh",
        "pr",
        "view",
        str(pr),
        "--repo",
        owner_repo,
        "--json",
        "author,commits,url,number,title,state",
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr or proc.stdout or "gh pr view failed")
    return json.loads(proc.stdout)


def guard_from_gh(
    owner_repo: str, pr: int, mrb_started_at: str | None = None
) -> dict[str, Any]:
    data = fetch_pr_commits(owner_repo, pr)
    author = ""
    if isinstance(data.get("author"), dict):
        author = str(data["author"].get("login") or "")
    commits = data.get("commits") if isinstance(data.get("commits"), list) else []
    verdict = analyze_commits(
        pr_author_login=author,
        commits=commits,
        mrb_started_at=mrb_started_at,
    )
    verdict["repo"] = owner_repo
    verdict["pr"] = int(pr)
    verdict["url"] = data.get("url")
    verdict["title"] = data.get("title")
    verdict["state"] = data.get("state")
    return verdict


def self_test() -> None:
    v = analyze_commits(
        pr_author_login="alice",
        commits=[
            {
                "oid": "aaa",
                "messageHeadline": "feat: thing",
                "authoredDate": "2026-09-25T12:00:00Z",
                "authors": [{"login": "alice"}],
            },
            {
                "oid": "bbb",
                "messageHeadline": "docs(MRB #56): sync README",
                "authoredDate": "2026-09-25T13:00:00Z",
                "authors": [{"login": "bob"}],
            },
        ],
    )
    assert v["flag"] is True and v["reason"] == "docs_mrb_commit_on_feature_branch", v

    v2 = analyze_commits(
        pr_author_login="alice",
        commits=[
            {
                "oid": "ccc",
                "messageHeadline": "fix: nits",
                "authoredDate": "2026-09-25T13:05:00Z",
                "authors": [{"login": "bob"}],
            }
        ],
        mrb_started_at="2026-09-25T13:00:00Z",
    )
    assert v2["flag"] is True and v2["reason"] == "foreign_commit_after_mrb_start", v2

    v3 = analyze_commits(
        pr_author_login="alice",
        commits=[
            {
                "oid": "ddd",
                "messageHeadline": "feat: ok",
                "authoredDate": "2026-09-25T12:00:00Z",
                "authors": [{"login": "alice"}],
            }
        ],
        mrb_started_at="2026-09-25T13:00:00Z",
    )
    assert v3["flag"] is False and v3["reason"] == "clean", v3
    print("self-test ok")


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--repo", default="")
    p.add_argument("--pr", type=int, default=0)
    p.add_argument("--mrb-started-at", default="", help="ISO time MRB began")
    p.add_argument("--json", action="store_true")
    p.add_argument("--self-test", action="store_true")
    p.add_argument("--fixture", default="", help="JSON: author.login + commits[]")
    args = p.parse_args(argv)
    if args.self_test:
        self_test()
        return 0
    if args.fixture:
        data = json.loads(Path_read(args.fixture))
        author = ""
        if isinstance(data.get("author"), dict):
            author = str(data["author"].get("login") or "")
        elif data.get("authorLogin"):
            author = str(data["authorLogin"])
        verdict = analyze_commits(
            pr_author_login=author,
            commits=list(data.get("commits") or []),
            mrb_started_at=args.mrb_started_at or data.get("mrbStartedAt"),
        )
    else:
        if not args.repo or not args.pr:
            p.error("--repo and --pr required (or --self-test / --fixture)")
        verdict = guard_from_gh(args.repo, args.pr, args.mrb_started_at or None)
    if args.json:
        print(json.dumps(verdict, indent=2))
    else:
        print(
            f"ok={verdict['ok']} flag={verdict['flag']} reason={verdict['reason']}"
        )
        if verdict.get("mrb_pending_announce"):
            print(verdict["mrb_pending_announce"])
    return 2 if verdict.get("flag") else 0


def Path_read(path: str) -> str:
    from pathlib import Path

    return Path(path).read_text(encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())

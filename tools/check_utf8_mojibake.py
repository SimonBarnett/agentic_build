#!/usr/bin/env python3
"""FR #347: fail on UTF-8 BOM or common mojibake in markdown (and optional paths).

Adopt in other fleet repos the same way agentic_irc did (tests/test_md_utf8_no_mojibake.py):
copy this script or the pytest, run from repo root.

Exit 0 = clean. Exit 1 = findings. Exit 2 = usage.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

UTF8_BOM = b"\xef\xbb\xbf"

# How common UTF-8 punctuation looks after a cp1252 (or latin-1) mis-decode
# and a second UTF-8 save. Built from codepoints so this source file stays clean.
MOJIBAKE_MARKERS = (
    "\u00e2\u20ac\u201d",  # em dash -> a-circ + euro + rdquo (common Windows form)
    "\u00e2\u20ac\u201c",  # en dash variant
    "\u00e2\u20ac\u2122",  # right single -> a-circ + euro + TM
    "\u00e2\u20ac\u02dc",  # left single
    "\u00e2\u20ac\u0153",  # left double
    "\u00e2\u20ac\u009d",  # right double (control)
    "\u00e2\u20ac\u00a2",  # bullet
    "\u00c3\u00a9",  # e-acute
    "\u00c3\u0097",  # times
    "\u00ef\u00bb\u00bf",  # BOM as text
)


def iter_md(root: Path):
    for p in root.rglob("*.md"):
        if ".git" in p.parts or "node_modules" in p.parts:
            continue
        yield p


def check_file(path: Path, root: Path) -> list[str]:
    errs: list[str] = []
    raw = path.read_bytes()
    rel = path.relative_to(root)
    if raw.startswith(UTF8_BOM):
        errs.append(f"{rel}: UTF-8 BOM")
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as e:
        errs.append(f"{rel}: not valid UTF-8 ({e})")
        return errs
    for marker in MOJIBAKE_MARKERS:
        if marker in text:
            errs.append(f"{rel}: mojibake {marker!r}")
    return errs


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--root",
        default=".",
        help="repo root (default: cwd)",
    )
    ap.add_argument(
        "paths",
        nargs="*",
        help="optional files/dirs; default = all *.md under root",
    )
    args = ap.parse_args(argv)
    root = Path(args.root).resolve()
    if not root.is_dir():
        print(f"not a directory: {root}", file=sys.stderr)
        return 2
    files: list[Path] = []
    if args.paths:
        for raw in args.paths:
            p = Path(raw)
            if not p.is_absolute():
                p = root / p
            p = p.resolve()
            if p.is_dir():
                files.extend(iter_md(p))
            elif p.is_file():
                files.append(p)
            else:
                print(f"missing: {p}", file=sys.stderr)
                return 2
    else:
        files = list(iter_md(root))
    all_errs: list[str] = []
    for p in sorted(set(files)):
        all_errs.extend(check_file(p, root))
    if all_errs:
        for e in all_errs:
            print(e, file=sys.stderr)
        print(f"FAIL utf8/mojibake: {len(all_errs)} finding(s)", file=sys.stderr)
        return 1
    print(f"ok: checked {len(files)} file(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

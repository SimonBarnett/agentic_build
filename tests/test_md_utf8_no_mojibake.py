"""Docs encoding: UTF-8 without BOM; no common mojibake (FR #347).

Mirrors agentic_irc tests/test_md_utf8_no_mojibake.py (FR #227).
"""
from __future__ import annotations

from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]

MOJIBAKE_MARKERS = (
    "\u00e2\u20ac\u201d",
    "\u00e2\u20ac\u201c",
    "\u00e2\u20ac\u2122",
    "\u00e2\u20ac\u02dc",
    "\u00e2\u20ac\u0153",
    "\u00e2\u20ac\u009d",
    "\u00e2\u20ac\u00a2",
    "\u00c3\u00a9",
    "\u00c3\u0097",
    "\u00ef\u00bb\u00bf",
)

UTF8_BOM = b"\xef\xbb\xbf"


def _md_files() -> list[Path]:
    out: list[Path] = []
    for p in ROOT.rglob("*.md"):
        if ".git" in p.parts or "node_modules" in p.parts:
            continue
        out.append(p)
    return sorted(out)


def test_readme_no_bom():
    p = ROOT / "README.md"
    raw = p.read_bytes()
    assert not raw.startswith(UTF8_BOM), "README.md must be UTF-8 without BOM"
    text = raw.decode("utf-8")
    assert "â€”" not in text, "README still has mojibake em-dash"


@pytest.mark.parametrize("path", _md_files(), ids=lambda p: str(p.relative_to(ROOT)))
def test_markdown_utf8_no_bom_no_mojibake(path: Path):
    raw = path.read_bytes()
    assert not raw.startswith(UTF8_BOM), f"{path.relative_to(ROOT)} has UTF-8 BOM"
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as e:
        pytest.fail(f"{path.relative_to(ROOT)} is not valid UTF-8: {e}")
    for marker in MOJIBAKE_MARKERS:
        assert marker not in text, (
            f"{path.relative_to(ROOT)} contains mojibake {marker!r} "
            f"(re-save as UTF-8 without BOM; see FR #347)"
        )


def test_check_script_self_clean():
    import subprocess
    import sys

    script = ROOT / "tools" / "check_utf8_mojibake.py"
    r = subprocess.run(
        [sys.executable, str(script), "--root", str(ROOT)],
        capture_output=True,
        text=True,
    )
    assert r.returncode == 0, r.stderr

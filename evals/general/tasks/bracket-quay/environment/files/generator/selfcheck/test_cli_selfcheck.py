"""Build-time pre-check: CLI build+check is clean (red on pristine, green fixed)."""

import os
import subprocess
import sys

from quaydoc.slugs import anchor_of

TITLES = ["Setup & First Steps", "FAQ: v2"]


def test_cli_check_is_clean(tmp_path):
    root = tmp_path / "docs"
    root.mkdir()
    (root / "index.qd").write_text(
        "---\ntitle: Home\n---\n\n" +
        "\n".join(f"- [[{t}]]" for t in TITLES) + "\n", encoding="utf-8")
    (root / "guide.qd").write_text(
        "---\ntitle: Guide\n---\n\n" +
        "\n".join(f"## {t}" for t in TITLES) + "\n", encoding="utf-8")
    outdir = str(tmp_path / "site")
    build = subprocess.run(
        [sys.executable, "-m", "quaydoc.cli", "build", str(root), "-o",
         outdir], capture_output=True, text=True)
    assert build.returncode == 0, build.stderr
    check = subprocess.run(
        [sys.executable, "-m", "quaydoc.cli", "check", outdir],
        capture_output=True, text=True)
    assert check.returncode == 0, check.stdout + check.stderr

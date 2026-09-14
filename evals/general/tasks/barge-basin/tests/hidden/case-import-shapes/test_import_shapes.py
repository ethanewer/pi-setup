"""Hidden case: calling styles the upstream example does not use.

The upstream example calls the helper as ``subprocess.check_output([], ...)``
after a plain ``import subprocess``.  These cases exercise the same code path
through different import/call shapes the analyzer must tolerate: an aliased
import, a ``from ... import`` of the callable itself, and a multiline call.
Each must scan with no internal error while still flagging the call.
"""
from __future__ import annotations

import subprocess
import sys

import pytest

CASES = {
    "aliased_import": (
        "import subprocess as sp\n"
        "sp.check_output([], stdout=None)\n"
    ),
    "from_import": (
        "from subprocess import check_output\n"
        "check_output([], stdout=None)\n"
    ),
    "multiline_call": (
        "import subprocess\n"
        "subprocess.check_output(\n"
        "    [],\n"
        "    stdout=None,\n"
        ")\n"
    ),
    "checked_kw_only": (
        "import subprocess\n"
        "subprocess.check_output([], stdout=None, input=b'')\n"
    ),
}


@pytest.mark.parametrize("name", sorted(CASES))
def test_import_style_scans_cleanly(tmp_path, name: str) -> None:
    t = tmp_path / "t.py"
    t.write_text(CASES[name])
    p = subprocess.run(
        [sys.executable, "-m", "bandit", str(t)],
        capture_output=True,
        text=True,
    )
    assert "internal error" not in (p.stderr or ""), p.stderr
    assert p.returncode in (0, 1), p.returncode
    assert "B404" in p.stdout, p.stdout
    assert "B603" in p.stdout, p.stdout
    assert "Files skipped (0)" in p.stdout, p.stdout
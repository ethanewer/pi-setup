"""Hidden case: regression guards for argument shapes that must NOT crash.

An empty list is the crashing shape; the same argument slot can legally hold a
non-empty list, a plain string, a tuple, or a variable.  None of these ever
caused the internal error, and the fix must not change how they scan: no
internal error, the same ordinary subprocess findings reported, and the file
still scanned (never skipped).
"""
from __future__ import annotations

import subprocess
import sys

import pytest

CASES = {
    "nonempty_list": (
        "import subprocess\n"
        "subprocess.check_output(['/bin/ls', '-l'], stdout=None)\n"
    ),
    "string_arg": (
        "import subprocess\n"
        "subprocess.check_output('ls -l', stdout=None)\n"
    ),
    "tuple_arg": (
        "import subprocess\n"
        "subprocess.check_output(('ls', '-l'), stdout=None)\n"
    ),
    "variable_arg": (
        "import subprocess\n"
        "cmd = '/bin/ls -l'\n"
        "subprocess.check_output(cmd, stdout=None)\n"
    ),
    "mixed_list": (
        "import subprocess\n"
        "subprocess.check_output(['sh', '-c', 'ls -l'], stdout=None)\n"
    ),
}


@pytest.mark.parametrize("name", sorted(CASES))
def test_guard_shape_scans_without_crashing(tmp_path, name: str) -> None:
    t = tmp_path / "t.py"
    t.write_text(CASES[name])
    p = subprocess.run(
        [sys.executable, "-m", "bandit", str(t)],
        capture_output=True,
        text=True,
    )
    assert p.returncode in (0, 1), p.returncode
    assert "internal error" not in (p.stderr or ""), p.stderr
    assert "B404" in p.stdout, p.stdout
    assert "Files skipped (0)" in p.stdout, p.stdout
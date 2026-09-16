"""Hidden case: every standard-library subprocess helper with an empty list.

Exercises the same crashed code path as the upstream regression example
(``subprocess.check_output([], stdout=None)``) but through the other helpers
of the same family that the upstream test does not use: Popen, call,
check_call, run as well as check_output.  Each scan must complete with no
"Bandit internal error" line on stderr and must still report the ordinary
findings (B404 blacklist import, B603 subprocess call) that the repaired
analyzer produces for this family.
"""
from __future__ import annotations

import subprocess
import sys

import pytest

CASES = {
    "popen": "import subprocess\nsubprocess.Popen([])\n",
    "call": "import subprocess\nsubprocess.call([])\n",
    "check_call": "import subprocess\nsubprocess.check_call([], stdout=None)\n",
    "check_output": "import subprocess\nsubprocess.check_output([], stdout=None)\n",
    "run": "import subprocess\nsubprocess.run([], stdout=None)\n",
}


@pytest.mark.parametrize("name", sorted(CASES))
def test_empty_list_helper_scans_cleanly(tmp_path, name: str) -> None:
    t = tmp_path / "t.py"
    t.write_text(CASES[name])
    p = subprocess.run(
        [sys.executable, "-m", "bandit", str(t)],
        capture_output=True,
        text=True,
    )
    assert "internal error" not in (p.stderr or ""), p.stderr
    assert p.returncode in (0, 1), p.returncode  # 1 = issues found; never a crash
    assert "B404" in p.stdout, p.stdout
    assert "B603" in p.stdout, p.stdout
    assert "Files skipped (0)" in p.stdout, p.stdout
"""Hidden case: empty-tuple subscripts in unusual positions, checked clean.

The upstream regression test only uses module-level annotations. This case
exercises the same visit_subscript path from return annotations, function-body
annotations, direct imports, class attributes and nested subscripts, and
requires a completely clean, crash-free run.
"""

import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SRC = "/app/src"
FIXTURE = str(HERE / "fixture_positions.py")

EXT_ARGS = [
    "--disable=all",
    "--enable=unnecessary-default-type-args",
    "--load-plugins=pylint.extensions.typing",
    "--score=n",
]


def run_pylint() -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, "-m", "pylint", FIXTURE] + EXT_ARGS,
        cwd=SRC,
        capture_output=True,
        text=True,
        timeout=180,
    )


def test_empty_tuple_in_unusual_positions_checks_cleanly():
    r = run_pylint()
    out = (r.stdout or "") + (r.stderr or "")
    assert "Fatal error" not in out, out
    assert "IndexError" not in out, out
    assert r.returncode == 0, "pylint exit status %d, output:\n%s" % (r.returncode, out)
    assert "unnecessary-default-type-args" not in out, out


def test_every_fixture_line_contains_a_crashing_shape():
    src = (HERE / "fixture_positions.py").read_text()
    for needle in ("ca.Generator[()]", "ca.AsyncGenerator[()]", "AsyncGenerator[()]"):
        assert needle in src
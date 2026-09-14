"""Hidden case: corner shapes around the empty-tuple trigger.

typing-module aliases, empty-tuple subscripts nested inside other subscripts,
and a plain three-argument Generator subscript must all check cleanly with the
typing extension enabled: exit 0, no crash markers, no messages.
"""

import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SRC = "/app/src"
FIXTURE = str(HERE / "fixture_corner_shapes.py")

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


def test_corner_shapes_check_cleanly():
    r = run_pylint()
    out = (r.stdout or "") + (r.stderr or "")
    assert "Fatal error" not in out, out
    assert "IndexError" not in out, out
    assert r.returncode == 0, "pylint exit status %d, output:\n%s" % (r.returncode, out)
    assert r.stdout.strip() == "", "expected no messages, got:\n%s" % out


def test_fixture_uses_nested_and_typed_alias_shapes():
    src = (HERE / "fixture_corner_shapes.py").read_text()
    for needle in ("t.Generator[()]", "t.AsyncGenerator[()]",
                   "tuple[ca.AsyncGenerator[()], ca.Generator[()]]",
                   "list[ca.Generator[()]]", "ca.Generator[int, str, str]"):
        assert needle in src
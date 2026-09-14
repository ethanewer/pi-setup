"""Hidden case: the redundant-default-type-args message survives the fix.

The upstream regression test asserts these messages only at module level. This
case requires the same messages (with the same shortened suggestion) from
function-body annotations, class attributes and method return annotations, and
nothing else — no crash, no spurious messages.
"""

import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SRC = "/app/src"
FIXTURE = str(HERE / "fixture_message_preservation.py")

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


def test_message_still_emitted_in_non_module_positions():
    r = run_pylint()
    out = (r.stdout or "") + (r.stderr or "")
    assert "Fatal error" not in out, out
    assert "IndexError" not in out, out
    # R6007 unnecessary-default-type-args, one per None-default subscript
    # (plural: a, b, attr, method-return annotation).
    assert r.stdout.count("unnecessary-default-type-args") == 4, out
    assert r.stdout.count("ca.Generator[int]") == 2, out
    assert r.stdout.count("ca.AsyncGenerator[int]") == 2, out
    # refactor-category exit code, nothing fatal
    assert r.returncode == 8, "pylint exit status %d, output:\n%s" % (r.returncode, out)
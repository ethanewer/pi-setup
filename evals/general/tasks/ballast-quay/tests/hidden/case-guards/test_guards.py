"""Hidden case: non-mixed implicit concatenation must STILL emit W1404.

The fix exempts only juxtapositions of a raw literal with a non-raw one
(which can never be merged into a single literal). Everything else the check
exists for must still be reported: plain/plain, raw/raw and unicode/unicode
juxtapositions in an assignment, list, tuple, call, dict value or bare
expression are exactly the forgotten-comma case and must keep firing
``implicit-str-concat``. This case guards against an over-broad fix that
silences the check entirely.
"""
import subprocess
import sys
import tempfile
from pathlib import Path

SAMPLES = [
    'G1 = "a" "b"',
    'G2 = ["a" "b"]',
    'G3 = ("a" "b", "c")',
    'print("x" "y")',
    'def f():\n    x = "a" "b"\n    return x',
    'G4 = {"a" "b"}',
    r'E = R"p" R"q"',
    'F = u"p" u"q"',
]


def run_pylint(src: str) -> subprocess.CompletedProcess:
    with tempfile.TemporaryDirectory() as td:
        path = Path(td) / "guard.py"
        path.write_text(src)
        return subprocess.run(
            [
                sys.executable,
                "-m",
                "pylint",
                str(path),
                "--disable=all",
                "--enable=implicit-str-concat",
                "--score=n",
            ],
            capture_output=True,
            text=True,
        )


def test_plain_concatenation_still_reported() -> None:
    for i, src in enumerate(SAMPLES):
        result = run_pylint(src)
        out = result.stdout + result.stderr
        assert "W1404" in out and "implicit-str-concat" in out, (
            f"sample {i} {src!r}: expected W1404\n{out}"
        )
        assert result.returncode != 0, (
            f"sample {i} {src!r}: expected a nonzero exit for a reported message\n{out}"
        )
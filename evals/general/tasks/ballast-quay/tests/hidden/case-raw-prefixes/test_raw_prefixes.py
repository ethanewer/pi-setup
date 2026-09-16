"""Hidden case: mixed raw/non-raw concatenation must never emit W1404.

Shapes the upstream regression test does not use: an uppercase ``R`` prefix,
combinations of ``u``- and ``R``-prefixed literals, triple-quoted raw
literals, raw concatenation inside a set, a dict value, a function call, a
``return`` statement, and a conditional expression. Every sample is an
implicit concatenation of a raw literal with a non-raw one, so on the fixed
tree none of them may produce ``implicit-str-concat`` (and every one of them
does produce it on the buggy tree, which is what makes this case sensitive).

The samples are driven through the installed pylint end-to-end, mirroring the
command the task's reproduction uses.
"""
import subprocess
import sys
import tempfile
from pathlib import Path

SAMPLES = [
    r"[R'\d+' '\d']",
    r"{r'[a-z]+' '[A-Z]+'}",
    r"{'pat': u'\w+' R'\w+'}",
    "print(r'''x''' 'y')",
    'def g():\n    x = r"a" "b"\n    return x',
    r"COND = (r'a' 'b') if r'c' 'd' else None",
]


def run_pylint(src: str) -> subprocess.CompletedProcess:
    with tempfile.TemporaryDirectory() as td:
        path = Path(td) / "sample.py"
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


def test_no_warning_for_any_mixed_raw_shape() -> None:
    for i, src in enumerate(SAMPLES):
        result = run_pylint(src)
        out = result.stdout + result.stderr
        assert result.returncode == 0, (
            f"sample {i} {src!r}: pylint exit {result.returncode}\n{out}"
        )
        assert "implicit-str-concat" not in out, (
            f"sample {i} {src!r}: unexpected W1404\n{out}"
        )
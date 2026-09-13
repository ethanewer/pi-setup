"""Hidden case: multi-literal chains.

A chain of three adjacent string literals is parsed as a single Const whose
token index is the FIRST literal, so the whole chain is either reported once
or not at all. The fix must treat the chain by its raw/plain boundary:
``[r"a" "b" "c"]`` and ``["a" r"b" "c"]`` start with a mixed raw/plain
boundary and must be silent, while the all-plain chain ``["a" "b" "c"]``
must still be reported exactly once. The upstream regression test never
exercises chains longer than two literals.
"""
import subprocess
import sys
import tempfile
from pathlib import Path

SILENT = [
    r'M1 = [r"a" "b" "c"]',
    r'M2 = ["a" r"b" "c"]',
]

WARNED = r'W3 = ["a" "b" "c"]'


def run_pylint(src: str) -> subprocess.CompletedProcess:
    with tempfile.TemporaryDirectory() as td:
        path = Path(td) / "chain.py"
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


def test_mixed_boundary_chain_is_silent() -> None:
    for i, src in enumerate(SILENT):
        result = run_pylint(src)
        out = result.stdout + result.stderr
        assert result.returncode == 0, (
            f"sample {i} {src!r}: pylint exit {result.returncode}\n{out}"
        )
        assert "implicit-str-concat" not in out, (
            f"sample {i} {src!r}: unexpected W1404\n{out}"
        )


def test_all_plain_chain_still_reported_once() -> None:
    result = run_pylint(WARNED)
    out = result.stdout + result.stderr
    assert result.returncode != 0, f"expected W1404 for {WARNED!r}\n{out}"
    assert out.count("implicit-str-concat") == 1, (
        f"expected exactly one W1404 for {WARNED!r}\n{out}"
    )
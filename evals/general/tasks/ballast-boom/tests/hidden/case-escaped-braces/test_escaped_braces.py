"""Hidden case: redaction of escaped (doubled) curly braces in f-strings.

Exercises the same string-redaction code path as the upstream regression test
but from inputs that test does not use: escaped braces without fields, escaped
braces around a field, a bare ``{{}}`` pair, and an f-string embedded in a
call. Each assertion checks the exact logical line a flake8 plugin receives;
every expected value below was measured against the repaired tree on Python
3.12 and is satisfied only when the redaction step counts escaped braces
against the raw token span.
"""
from __future__ import annotations

import os
import pathlib

import pytest

from flake8.main.cli import main


def yields_logical_line(logical_line):  # logical-line plugin API
    yield 0, f"T001 {logical_line!r}"


CFG = f"""\
[flake8]
extend-ignore = F
[flake8:local-plugins]
extension =
    T = {yields_logical_line.__module__}:{yields_logical_line.__name__}
"""

# (physical line, expected redacted logical line on Python 3.12)
CASES = [
    ("f'{{a}}'", "f'xxxxx'"),
    ("f'{{{value}}}'", "f'xx{value}xx'"),
    ("f'{{x}}{x}'", "f'xxxxx{x}'"),
    ("print(f'{{ok}}')", "print(f'xxxxxx')"),
    ("f'{{}}'", "f'xxxx'"),
]


@pytest.mark.parametrize(("src", "expected"), CASES)
def test_escaped_braces_redact_to_the_right_spans(
    tmp_path: pathlib.Path, capsys, src: str, expected: str
) -> None:
    (tmp_path / "t.py").write_text(src + "\n")
    (tmp_path / "tox.ini").write_text(CFG)
    cwd = os.getcwd()
    os.chdir(tmp_path)
    try:
        nerr = main(("t.py", "--config", "tox.ini"))
    finally:
        os.chdir(cwd)
    out, err = capsys.readouterr()
    assert nerr == 1
    assert out.rstrip("\n") == f"t.py:1:1: T001 {expected!r}"
    assert err == ""


def test_reported_line_covers_the_whole_physical_line(tmp_path, capsys) -> None:
    """Regression shape: column bookkeeping must not shift across escapes.

    With the miscount, filler and raw characters swap places and the logical
    line no longer corresponds 1:1 to the physical line; the length-based
    check catches misalignment even where a stray brace happens to land.
    """
    for src, expected in CASES:
        (tmp_path / "t.py").write_text(src + "\n")
        (tmp_path / "tox.ini").write_text(CFG)
        cwd = os.getcwd()
        os.chdir(tmp_path)
        try:
            main(("t.py", "--config", "tox.ini"))
        finally:
            os.chdir(cwd)
        out, _ = capsys.readouterr()
        report = out.strip().splitlines()[0]
        assert report == f"t.py:1:1: T001 {expected!r}"
        # the redacted logical line must span exactly the physical line
        assert len(eval(report.split("T001 ", 1)[1])) == len(src)
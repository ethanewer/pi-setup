"""Hidden case: redaction of everything the fix must NOT change.

The fix concerns only escaped braces inside f-strings on Python 3.12. Plain
strings containing doubled braces, f-strings without escaped braces, raw
strings, triple-quoted f-strings, nested format-spec braces, and lines with no
string at all must redact exactly as they did before the fix. Every expected
value below is unchanged between the parent commit and the fixed tree (each
was also measured on the buggy tree and is identical there).
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

# (physical line, expected redacted logical line: identical on parent and fix)
CASES = [
    ("s = '{{}}'", "s = 'xxxx'"),
    ("f'hello {name}'", "f'xxxxxx{name}'"),
    ("r'a{{b}}'", "r'xxxxxx'"),
    ("x = 1 + 2  # keep", "x = 1 + 2"),
    ("f'plain {x} text'", "f'xxxxxx{x}xxxxx'"),
    ("f'{val:{width}}'", "f'{val:{width}}'"),
    ('f"""doc {x}"""', 'f"""xxxx{x}"""'),
]


@pytest.mark.parametrize(("src", "expected"), CASES)
def test_non_escaped_brace_redaction_is_unchanged(
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
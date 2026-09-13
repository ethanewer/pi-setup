"""Hidden case: escaped-brace f-strings next to other f-string features.

Same redaction code path as the upstream regression test, different inputs:
escaped braces around quoted literal content, between two replacement fields,
with a second f-string on the same physical line, and with quadruple braces
before a field. A second error from the same plugin reports the length of the
logical line it received, which must equal the physical line length after the
fix (the buggy miscount shifts filler and raw characters, corrupting the
logical line).
"""
from __future__ import annotations

import os
import pathlib

import pytest

from flake8.main.cli import main


def yields_logical_line_and_length(logical_line):  # logical-line plugin API
    yield 0, f"T001 {logical_line!r}"
    yield 0, f"T002 len={len(logical_line)}"


CFG = f"""\
[flake8]
extend-ignore = F
[flake8:local-plugins]
extension =
    T = {yields_logical_line_and_length.__module__}:{yields_logical_line_and_length.__name__}
"""

# (physical line, expected redacted logical line on Python 3.12)
CASES = [
    ('x = f\'{{"depth": {d}}}\'', 'x = f\'xxxxxxxxxxx{d}xx\''),
    ("f'{a}{{sep}}{b}'", "f'{a}xxxxxxx{b}'"),
    ("f'{{x}}' f'{{y}}'", "f'xxxxx' f'xxxxx'"),
    ("f'{{{{probe}}}}: {v}'", "f'xxxxxxxxxxxxxxx{v}'"),
]


@pytest.mark.parametrize(("src", "expected"), CASES)
def test_escaped_braces_adjacent_to_other_features(
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
    assert nerr == 1  # flake8's exit code: 1 when any error is reported
    lines = out.strip().splitlines()
    t001 = next(l for l in lines if ": T001 " in l)
    t002 = next(l for l in lines if ": T002 " in l)
    assert t001 == f"t.py:1:1: T001 {expected!r}"
    assert t002 == f"t.py:1:1: T002 len={len(src)}"
    assert err == ""


def test_no_raw_characters_leak_from_literal_regions(tmp_path, capsys) -> None:
    """The redacted line must be pure filler + verbatim fields, no leftovers.

    At the parent commit the miscount lets characters from the physical line
    leak into the logical line (e.g. ``{``/``}`` right after an escaped pair,
    or separate escaped pairs collapsing onto each other). After the fix every
    literal character is an ``x`` and — apart from the f-string expression
    fields — no ``{``/``}`` and no quote from inside the string survives.
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
        t001 = next(l for l in out.strip().splitlines() if ": T001 " in l)
        logical = eval(t001.split("T001 ", 1)[1])
        assert logical == expected
        # literal regions contain no stray braces and no stray quotes
        body = logical.split("f'", 1)[1][:-1] if logical.startswith("f'") else logical
        assert "{{" not in body
        assert "}}" not in body
        assert '"' not in body
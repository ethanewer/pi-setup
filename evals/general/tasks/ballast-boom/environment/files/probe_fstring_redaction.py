#!/usr/bin/env python3
"""Probe for flake8's escaped-brace f-string redaction bug.

On Python 3.12 the tokenizer exposes the *parsed* form of an escaped (doubled)
curly brace inside an f-string (a single ``{``) while the token's end column
accounts for the raw double-brace span. flake8's string-redaction step
replaces the FSTRING_MIDDLE text with filler characters using only the parsed
length, so on the very next token the column bookkeeping is off by one per
escaped brace and raw characters from the physical line leak into the logical
line that plugins receive.

A flake8 logical-line plugin (see probe_plugin.py) reports the logical line it
was handed. When the bug is present the report for an f-string that uses
escaped braces is garbled: filler characters and stray raw characters are
misplaced. This probe runs flake8 on several samples and compares each
reported line against the correctly redacted form (on Python 3.12, an escaped
brace pair is replaced by two filler characters; replacement fields are left
verbatim and every other literal character becomes a filler character).

Exit status: 0 once every sample is reported correctly, 1 while the bug is
present.
"""
from __future__ import annotations

import contextlib
import io
import os
import pathlib
import sys
import tempfile

from flake8.main.cli import main as flake8_main
from probe_plugin import yields_logical_line

# (physical line, correctly redacted logical line on Python 3.12)
SAMPLES = [
    (
        'f\'{{"{hello}": "{world}"}}\'',
        'f\'xxx{hello}xxxx{world}xxx\'',
    ),
    (
        "f'{{{value}}}'",
        "f'xx{value}xx'",
    ),
]

CFG = f"""\
[flake8]
extend-ignore = F
[flake8:local-plugins]
extension =
    T = {yields_logical_line.__module__}:{yields_logical_line.__name__}
"""


class Capture:
    """Minimal stdout stand-in exposing .buffer, which flake8's formatter uses."""

    def __init__(self) -> None:
        self._s = io.StringIO()
        self.buffer = self

    def write(self, data: str) -> int:
        if isinstance(data, bytes):
            data = data.decode("utf-8")
        return self._s.write(data)

    def isatty(self) -> bool:
        return False

    def getvalue(self) -> str:
        return self._s.getvalue()


def run_flake8(tmp: pathlib.Path, src: str) -> str:
    (tmp / "t.py").write_text(src + "\n")
    (tmp / "tox.ini").write_text(CFG)
    cwd = os.getcwd()
    os.chdir(tmp)
    try:
        cap = Capture()
        old = sys.stdout
        sys.stdout = cap
        try:
            flake8_main(("t.py", "--config", "tox.ini"))
        finally:
            sys.stdout = old
        return cap.getvalue().strip()
    finally:
        os.chdir(cwd)


def main() -> int:
    failures = 0
    with tempfile.TemporaryDirectory() as td:
        tmp = pathlib.Path(td)
        for src, expected in SAMPLES:
            got = run_flake8(tmp, src)
            expected_line = f't.py:1:1: T001 {expected!r}'
            print(f"source   : {src}")
            print(f"reported : {got!r}")
            print(f"expected : {expected_line!r}")
            if expected_line in got.splitlines():
                print("  -> OK: the logical line handed to the plugin is correctly redacted")
            else:
                print("  -> BUG: the plugin received a garbled, misaligned logical line")
                failures += 1
            print()
    if failures:
        print(
            f"{failures} sample(s) are reported incorrectly: the string "
            "redaction step miscounts escaped braces in f-strings."
        )
        return 1
    print("All samples are reported correctly.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
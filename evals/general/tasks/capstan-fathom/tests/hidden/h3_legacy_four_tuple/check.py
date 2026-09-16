#!/usr/bin/env python3
"""Hidden case h3 for capstan-fathom.

The legacy four-element detail tuple (Python 3.9 and earlier, and older byte
compilers) must keep producing exactly the positions it always produced:
column decremented by one, clamped to the length of the offending logical
line. The fix must leave this pre-existing behaviour untouched, so on a
fixed tree these return the same results they returned before the bug.
"""
import sys

sys.path.insert(0, "/app/src/src")

from unittest import mock  # noqa: E402

from flake8 import checker  # noqa: E402

CASES = [
    (SyntaxError("invalid syntax", ("mod.py", 3, 9, "payload that is longer than column\n")),
     (3, 8)),
    (SyntaxError("invalid syntax", ("mod.py", 7, 5, "x\n")), (7, 0)),
    (SyntaxError("invalid syntax", ("mod.py", 1, 4, "foo(\n")), (1, 3)),
]


def main() -> int:
    fc = checker.FileChecker("-", {}, mock.MagicMock())
    extract = fc._extract_syntax_information
    for err, expected in CASES:
        try:
            actual = extract(err)
        except Exception as e:  # noqa: BLE001
            print(f"extract crashed on legacy 4-tuple: {type(e).__name__}: {e}")
            return 1
        if actual != expected:
            print(f"expected {expected}, got {actual} for {err.args[1]!r}")
            return 1
        print(f"ok: legacy 4-tuple {err.args[1]!r} -> {actual}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
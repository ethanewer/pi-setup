#!/usr/bin/env python3
"""Hidden case h2 for capstan-fathom.

3.10+ six-element detail tuples in shapes the upstream regression test does
not use: source text unavailable (text is None, which the parser does when
it cannot recover the failing line) and end-fields pointing at a different
position than the start.  Both crash the buggy parent with AttributeError;
on a fixed tree the position recovery must return exactly the (line, column)
the exception carries.
"""
import sys

sys.path.insert(0, "/app/src/src")

from unittest import mock  # noqa: E402

from flake8 import checker  # noqa: E402

CASES = [
    (SyntaxError("invalid syntax", ("mod.py", 5, 3, None, 5, 8)), (5, 3)),
    (SyntaxError("invalid syntax", ("mod.py", 2, 7, "if x == :\n", 4, 3)), (2, 7)),
]


def main() -> int:
    fc = checker.FileChecker("-", {}, mock.MagicMock())
    extract = fc._extract_syntax_information
    for err, expected in CASES:
        try:
            actual = extract(err)
        except Exception as e:  # noqa: BLE001
            print(f"extract crashed: {type(e).__name__}: {e}")
            return 1
        if actual != expected:
            print(f"expected {expected}, got {actual} for {err.args[1]!r}")
            return 1
        print(f"ok: {err.args[1]!r} -> {actual}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
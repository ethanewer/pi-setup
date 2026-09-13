#!/usr/bin/env python3
"""Hidden case h4 for capstan-fathom.

The neighbouring branches of the same position-recovery routine must keep
behaving: a tokenize.TokenError carries a direct (row, column) pair, and an
exception with no location detail falls back to (1, 0). Neither path may be
disturbed by the fix.
"""
import sys
import tokenize

sys.path.insert(0, "/app/src/src")

from unittest import mock  # noqa: E402

from flake8 import checker  # noqa: E402

CASES = [
    (tokenize.TokenError("EOF in multi-line statement", (4, 12)), (4, 12)),
    (Exception("boom"), (1, 0)),
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
            print(f"expected {expected}, got {actual} for {type(err).__name__}({err.args!r})")
            return 1
        print(f"ok: {type(err).__name__} {err.args!r} -> {actual}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
#!/usr/bin/env python3
"""Hidden case h1 for capstan-fathom.

Real parse failures of multi-line modules, raised by the actual CPython 3.12
parser (the upstream regression test only builds a single-line detail tuple
by hand). On the buggy parent every one of these crashes with
AttributeError; on a fixed tree the position recovery must return exactly
the (line, column) the exception carries.
"""
import sys

sys.path.insert(0, "/app/src/src")

from unittest import mock  # noqa: E402

from flake8 import checker  # noqa: E402

# (source that fails to parse, expected recovered (line, column))
SNIPPETS = [
    ("import os\n\nvalues = {1: 'a',\n          2: 'b',\n          3: 'c' + ]\n",
     (5, 20)),
    ("def build():\n    return {\n        'x': 1,\n    }\n\nif True print('nope')\n",
     (6, 9)),
    ("total = 0\nfor i in range(10):\n    total += i\n\nclass A(:\n    pass\n",
     (5, 9)),
]


def main() -> int:
    fc = checker.FileChecker("-", {}, mock.MagicMock())
    extract = fc._extract_syntax_information
    for src, expected in SNIPPETS:
        err = None
        try:
            compile(src, "<snippet>", "exec")
        except SyntaxError as e:  # noqa: BLE001
            err = e
        if err is None:  # pragma: no cover
            print(f"unexpected: snippet compiled cleanly: {src!r}")
            return 1
        try:
            actual = extract(err)
        except Exception as e:  # noqa: BLE001
            print(f"extract crashed on a real parse failure: {type(e).__name__}: {e}")
            return 1
        if actual != expected:
            print(f"expected {expected}, got {actual} for {src!r}")
            return 1
        print(f"ok: real parse failure {err.args[1][0:3]!r} -> {actual}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
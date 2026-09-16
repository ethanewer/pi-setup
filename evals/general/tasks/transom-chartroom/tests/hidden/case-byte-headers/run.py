#!/usr/bin/env python3
"""Hidden case: byte header parts and newline-then-whitespace value variants.

Exercises the same header-validity code path as the upstream regression test
with inputs that test does not use: bytes header names/values, and str values
whose trailing newline is preceded by whitespace (space / tab), which the
buggy '$' anchor also let through.
"""
import sys

import requests
from requests.exceptions import InvalidHeader
from requests.utils import check_header_validity

MUST_REJECT = [
    ("foo", b"bar\n"),
    (b"foo\n", "bar"),
    ("foo", b"\n"),
    (b"foo", b"bar\n"),
    ("foo", "bar\t\n"),
    ("foo", "bar \n"),
]

MUST_ACCEPT = [
    ("foo", b"bar"),
    (b"foo", b"bar"),
    ("foo", "plain"),
    ("foo-bar", "value"),
]


def main() -> int:
    problems = []
    for name, value in MUST_REJECT:
        try:
            check_header_validity((name, value))
        except InvalidHeader:
            continue
        problems.append(
            f"BUG: header {name!r}: {value!r} was ACCEPTED; must raise InvalidHeader"
        )
    for name, value in MUST_ACCEPT:
        try:
            check_header_validity((name, value))
        except InvalidHeader as exc:
            problems.append(f"REGRESSION: {name!r}: {value!r} rejected: {exc}")
    if problems:
        for problem in problems:
            print(problem, file=sys.stderr)
        print("HIDDEN CASE BYTES: FAILED", file=sys.stderr)
        return 1
    print("HIDDEN CASE BYTES: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
#!/usr/bin/env python3
"""Reference reproduction script for the trailing-newline header bug.

Contract (also stated in instruction.md):
  * imports requests as installed, does not touch sys.path,
  * exits 0 IFF every header name/value that ends with a newline character
    raises requests.exceptions.InvalidHeader via the public API
    requests.utils.check_header_validity, and a plain valid header does NOT
    raise,
  * exits non-zero (printing the failures to stderr) otherwise.
"""
import sys

import requests
from requests.exceptions import InvalidHeader
from requests.utils import check_header_validity

# Header pairs whose name or value ends with a newline character. Each of them
# must be rejected with InvalidHeader.
MUST_REJECT = [
    ("foo", "bar\n"),
    ("foo\n", "bar"),
    ("foo", "\n"),
    ("foo", "bar\r\n"),
    ("foo", "\r\n"),
]

# Plain, valid header pairs that must keep passing.
MUST_ACCEPT = [
    ("foo", "bar"),
    ("content-type", "text/plain"),
]


def main() -> int:
    problems = []
    for name, value in MUST_REJECT:
        try:
            check_header_validity((name, value))
        except InvalidHeader:
            continue
        problems.append(
            f"BUG: header {name!r}: {value!r} was ACCEPTED - requests must "
            f"raise InvalidHeader for header names/values ending with a "
            f"newline character"
        )
    for name, value in MUST_ACCEPT:
        try:
            check_header_validity((name, value))
        except InvalidHeader as exc:
            problems.append(
                f"REGRESSION: valid header {name!r}: {value!r} was rejected: {exc}"
            )
    if problems:
        for problem in problems:
            print(problem, file=sys.stderr)
        print("FAILED", file=sys.stderr)
        return 1
    print("OK: header names/values ending with a newline are rejected")
    return 0


if __name__ == "__main__":
    sys.exit(main())
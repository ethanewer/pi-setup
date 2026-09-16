#!/usr/bin/env python3
"""Apply the RFC 6265 ASCII-only cookie-expiry fix to aiohttp's cookiejar.py.

The five DATE_*_RE regexes relied on Python's Unicode meaning of \\d (and of
the month/token classes), so dates with non-ASCII decimal digits were accepted
as valid expiry timestamps.  This adds the re.ASCII flag to each of them so the
parser returns None for such dates, per RFC 6265 section 5.1.1, while ASCII
dates keep their exact current semantics.  Idempotent; exits non-zero if the
expected snippets are not all present and applied.
"""

import sys
from pathlib import Path

REPLACEMENTS = [
    (
        '        r"(?P<token>[\\x00-\\x08\\x0A-\\x1F\\d:a-zA-Z\\x7F-\\xFF]+)"\n    )',
        '        r"(?P<token>[\\x00-\\x08\\x0A-\\x1F\\d:a-zA-Z\\x7F-\\xFF]+)",\n        re.ASCII,\n    )',
    ),
    (
        'DATE_HMS_TIME_RE = re.compile(r"(\\d{1,2}):(\\d{1,2}):(\\d{1,2})")',
        'DATE_HMS_TIME_RE = re.compile(r"(\\d{1,2}):(\\d{1,2}):(\\d{1,2})", re.ASCII)',
    ),
    (
        'DATE_DAY_OF_MONTH_RE = re.compile(r"(\\d{1,2})")',
        'DATE_DAY_OF_MONTH_RE = re.compile(r"(\\d{1,2})", re.ASCII)',
    ),
    (
        '        "(jan)|(feb)|(mar)|(apr)|(may)|(jun)|(jul)|(aug)|(sep)|(oct)|(nov)|(dec)",\n        re.I,\n    )',
        '        "(jan)|(feb)|(mar)|(apr)|(may)|(jun)|(jul)|(aug)|(sep)|(oct)|(nov)|(dec)",\n        re.I | re.ASCII,\n    )',
    ),
    (
        'DATE_YEAR_RE = re.compile(r"(\\d{2,4})")',
        'DATE_YEAR_RE = re.compile(r"(\\d{2,4})", re.ASCII)',
    ),
]

EXPECTED_ASCII_COUNT = 5


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: fix_cookiejar.py PATH", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    src = path.read_text(encoding="utf-8")

    if src.count("re.ASCII") >= EXPECTED_ASCII_COUNT:
        print("cookiejar.py already carries the ASCII-only flags")
        return 0

    applied = 0
    for old, new in REPLACEMENTS:
        if old in src:
            src = src.replace(old, new, 1)
            applied += 1
        elif new in src:
            applied += 1  # already applied by a previous run
        else:
            print("FATAL: expected snippet not found in source:", file=sys.stderr)
            print(old, file=sys.stderr)
            return 1

    if applied != EXPECTED_ASCII_COUNT:
        print(f"FATAL: expected {EXPECTED_ASCII_COUNT} edits, applied {applied}", file=sys.stderr)
        return 1

    path.write_text(src, encoding="utf-8")
    print(f"ok: added re.ASCII to {EXPECTED_ASCII_COUNT} DATE_*_RE regexes in {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
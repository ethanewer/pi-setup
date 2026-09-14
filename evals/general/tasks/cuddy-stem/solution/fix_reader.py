#!/usr/bin/env python3
"""Apply the reserved-close-code fix to aiohttp's pure-Python WebSocket reader.

At the pinned parent commit aiohttp/_websocket/reader_py.py builds its
ALLOWED_CLOSE_CODES set from every member of the WSCloseCode enum, which
includes ABNORMAL_CLOSURE (1006).  RFC 6455 section 7.4.1 forbids 1006 on
the wire, so the fix excludes it from the allowed set and the reader raises a
PROTOCOL_ERROR for a received Close frame carrying status 1006, exactly as it
already does for the other reserved codes 1004, 1005 and 1015 (which are not
enum members and therefore were never in the set).  Idempotent; exits
non-zero if the expected snippet is not present in the source.
"""

import sys
from pathlib import Path

OLD = "ALLOWED_CLOSE_CODES: set[int] = {int(i) for i in WSCloseCode}"
NEW = (
    "ALLOWED_CLOSE_CODES: set[int] = {int(i) for i in WSCloseCode} "
    "- {int(WSCloseCode.ABNORMAL_CLOSURE)}"
)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: fix_reader.py PATH", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    src = path.read_text(encoding="utf-8")
    if NEW in src:
        print("reader_py.py already carries the fix")
        return 0
    if OLD not in src:
        print("FATAL: expected snippet not found in source:", file=sys.stderr)
        print(OLD, file=sys.stderr)
        return 1
    path.write_text(src.replace(OLD, NEW, 1), encoding="utf-8")
    print(f"ok: excluded ABNORMAL_CLOSURE (1006) from ALLOWED_CLOSE_CODES in {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
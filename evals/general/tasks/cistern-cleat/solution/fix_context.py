#!/usr/bin/env python3
"""Apply the upstream ClientIP multi-line forwarded-header fix to gin.

The bug: Context.ClientIP() fed only the FIRST value of each trusted header to
the engine's validateHeader(), so when a proxy chain appends several
X-Forwarded-For lines, every line after the first was ignored and the leftmost
address was reported instead of the rightmost untrusted one.  The upstream fix
joins ALL values of the header (comma-separated) before validation, making
the multi-line case equivalent to a single line carrying the same list.

Idempotent; exits non-zero if the expected snippet is not found exactly once.
"""

import sys
from pathlib import Path

OLD = '\t\t\tip, valid := c.engine.validateHeader(c.requestHeader(headerName))'
NEW = (
    '\t\t\theaderValue := strings.Join(c.Request.Header.Values(headerName), ",")\n'
    '\t\t\tip, valid := c.engine.validateHeader(headerValue)'
)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: fix_context.py PATH", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    src = path.read_text(encoding="utf-8")

    if src.count(OLD) == 0 and NEW in src:
        print("context.go already carries the multi-value header join")
        return 0
    if src.count(OLD) != 1:
        print(f"FATAL: expected anchor found {src.count(OLD)} times, not exactly once:",
              file=sys.stderr)
        print(OLD, file=sys.stderr)
        return 1

    path.write_text(src.replace(OLD, NEW, 1), encoding="utf-8")
    print(f"ok: ClientIP now joins all header lines before validation in {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
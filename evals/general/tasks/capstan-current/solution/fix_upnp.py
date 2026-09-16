#!/usr/bin/env python3
"""Apply the minimal upstream fix for the capstan-current bug.

replaceRawPath() in lib/upnp/upnp.go normalizes a discovered device's
control URL against the device's own location URL. For a relative control
URL it splits the query off, takes the path component `p`, and tests
`p[0] == '/'` — but when the control URL is a bare query string like
"?control=..." the path component is the empty string, so the `p[0]`
subscript panics at runtime with "index out of range [0] with length 0".
The fix guards the subscript with an empty-string check so a query-only
control URL keeps the base location's path and replaces only the query.

Usage: fix_upnp.py /app/src/lib/upnp/upnp.go
"""
import sys

BUGGY = """		if p[0] == '/' {"""
FIXED = """		if p != "" && p[0] == '/' {"""


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: fix_upnp.py PATH_TO_UPNP_GO", file=sys.stderr)
        return 2
    path = sys.argv[1]
    src = open(path, encoding="utf-8").read()
    count = src.count(BUGGY)
    if count != 1:
        print(f"error: expected exactly one occurrence of the buggy guard, found {count}", file=sys.stderr)
        return 1
    open(path, "w", encoding="utf-8").write(src.replace(BUGGY, FIXED))
    print(f"patched {path}: query-only control URLs no longer panic")
    return 0


if __name__ == "__main__":
    sys.exit(main())
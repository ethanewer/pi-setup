#!/usr/bin/env python3
"""Standalone reproduction for the float-route URL defect (deliverable).

Contract (see instruction.md Step 1):
  python3 reproduce.py [value]   (value defaults to 0.00001)
  prints  BUILT <url>            -- the URL the adapter builds for the value
  prints  ROUNDTRIP <endpoint> <value> -- what matching that URL back yields
  exits 0 iff the built URL contains no e/E, the round-trip succeeded and the
  matched value equals the input; otherwise prints FAIL: <reason> to stderr
  and exits non-zero.

On the pre-fix library this must FAIL (BUILT /1e-05, no round-trip); on a
repaired library it must PASS.
"""

import sys

import werkzeug.routing as r

DEFAULT = 0.00001


def main() -> int:
    value = float(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT
    m = r.Map([r.Rule("/<float:v>", endpoint="a")])
    adapter = m.bind("test.example")
    url = adapter.build("a", {"v": value})
    print(f"BUILT {url}")
    try:
        endpoint, params = adapter.match(url)
    except Exception as exc:  # werkzeug.exceptions.NotFound and friends
        print(f"FAIL: matching {url!r} raised {type(exc).__name__}: {exc}", file=sys.stderr)
        return 1
    print(f"ROUNDTRIP {endpoint} {params['v']}")
    if "e" in url or "E" in url:
        print(f"FAIL: URL for {value} contains scientific notation: {url}", file=sys.stderr)
        return 1
    if params["v"] != value:
        print(f"FAIL: round-tripped value {params['v']!r} != input {value!r}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
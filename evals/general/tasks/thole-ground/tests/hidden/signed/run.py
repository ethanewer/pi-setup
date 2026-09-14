#!/usr/bin/env python3
"""Hidden case: signed (negative) extreme floats must build matchable URLs.

Uses the signed converter option on the rule; the upstream regression test
does not touch signed rules or negative values. Exercises the sign-handling a
complete fix needs (negative scientific notation like -1.5e-08, plus negative
integer-valued floats whose naive fixed-point fix would emit '-5.').
"""

import re
import sys

import werkzeug.routing as r

VALUES = [-1.5e-08, -0.00001, -1e20, -5.0, 0.5, -3.25e18, -1000.0]


def main():
    m = r.Map([r.Rule("/<float(signed=True):v>", endpoint="a")])
    adapter = m.bind("test.example")
    converter = r.FloatConverter(m, signed=True)
    regex = converter.regex
    failures = 0
    for v in VALUES:
        url = adapter.build("a", {"v": v})
        if "e" in url or "E" in url:
            print(f"FAIL {v}: URL contains scientific notation: {url}")
            failures += 1
            continue
        if not re.fullmatch(regex, url.lstrip('/')):
            print(f"FAIL {v}: URL {url!r} does not match signed float regex {regex!r}")
            failures += 1
            continue
        endpoint, params = adapter.match(url)
        if (endpoint, params["v"]) != ("a", v):
            print(f"FAIL {v}: round-trip gave {(endpoint, params['v'])!r}")
            failures += 1
            continue
        print(f"ok {v} -> {url}")
    if failures:
        print(f"{failures} failure(s)")
        sys.exit(1)
    print("hidden case 'signed': all values round-trip OK")


if __name__ == "__main__":
    main()
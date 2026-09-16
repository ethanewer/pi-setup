#!/usr/bin/env python3
"""Hidden case: large and integer-valued floats must build matchable URLs.

The upstream regression test only covers 0.00001. These values exercise the
other end of the defect: very large magnitudes whose str() is scientific
(1e20, 1.5e16, 3.25e18) and integer-valued floats (5.0, 1000.0) that a naive
fixed-point fix renders with a bare trailing dot ('5.', '...000.') which the
converter regex rejects.
"""

import re
import sys

import werkzeug.routing as r

VALUES = [1e20, 5.0, 1000.0, 123456789.125, 1.5e16, 3.25e18]


def main():
    m = r.Map([r.Rule("/<float:v>", endpoint="a")])
    adapter = m.bind("test.example")
    regex = r.FloatConverter.regex
    failures = 0
    for v in VALUES:
        url = adapter.build("a", {"v": v})
        if "e" in url or "E" in url:
            print(f"FAIL {v}: URL contains scientific notation: {url}")
            failures += 1
            continue
        if not re.fullmatch(regex, url.lstrip('/')):
            print(f"FAIL {v}: URL {url!r} does not match float regex {regex!r}")
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
    print("hidden case 'large': all values round-trip OK")


if __name__ == "__main__":
    main()
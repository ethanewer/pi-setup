#!/usr/bin/env python3
"""Hidden case: tiny extreme-small floats must build matchable URLs.

Exact round-trip through the library's own build -> match machinery, on
values the upstream regression test (0.00001 only) does not use. Any fix that
only suppresses scientific notation for the golden value fails here: a naive
fixed-point formatter renders values like 2.5e-07 with fixed precision 6,
giving '0.' (a bare trailing dot the converter regex rejects).
"""

import re
import sys

import werkzeug.routing as r

VALUES = [7.5e-08, 9.9e-07, 1.1e-06, 0.0000999999, 4.44e-09]


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
    print("hidden case 'tiny': all values round-trip OK")


if __name__ == "__main__":
    main()
#!/usr/bin/env python3
"""Oracle fix for plimsoll-bell: apply the upstream kstest string-CDF fix to the checkout at /app/src.

The upstream change for scipy gh-25448 (one file, scipy/stats/_stats_py.py):
in `_parse_kstest_args`, string distribution names are resolved through the
full distribution class hierarchy (`getattr(distributions, data2).cdf`)
instead of the special-case mapping `{'norm': special.ndtr}`. The special
function `special.ndtr` accepts only (x[, out]) -> it cannot take the loc/
scale parameters passed via `args=`, so `kstest(x, "norm", args=(loc, scale))`
raised `TypeError: ndtr() takes from 1 to 2 positional arguments but 3 were
given` before the test ever ran. Resolving through `distributions.norm.cdf`
gives a CDF that accepts the location/scale arguments, matching what a
callable CDF receives.

The edit is anchored on the exact parent-commit bytes and fails loudly if the
checkout ever drifts, so a broken pin or an unexpected tree cannot silently
produce a wrong "fix".
"""
import sys

PATH = "/app/src/scipy/stats/_stats_py.py"

OLD = """    if isinstance(data2, str):
        special_distributions = {'norm': special.ndtr}
        cdf = special_distributions.get(data2, getattr(distributions, data2).cdf)
        data2 = None"""

NEW = """    if isinstance(data2, str):
        cdf = getattr(distributions, data2).cdf
        data2 = None"""


def main() -> int:
    with open(PATH, encoding="utf-8") as f:
        s = f.read()
    if OLD not in s:
        print(
            "ERROR: could not locate the parent-commit kstest argument-parsing "
            "code in %s; the checkout drifted from the pinned revision" % PATH,
            file=sys.stderr,
        )
        return 1
    if NEW in s:
        print("kstest string-CDF fix already present")
        return 0
    s = s.replace(OLD, NEW, 1)
    with open(PATH, "w", encoding="utf-8") as f:
        f.write(s)
    print("applied the kstest string-CDF fix to", PATH)
    return 0


if __name__ == "__main__":
    sys.exit(main())
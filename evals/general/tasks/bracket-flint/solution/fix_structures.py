#!/usr/bin/env python3
"""Fix the comma-terminated argnames bug in the /app/src pytest checkout.

The bug lives in `ParameterSet._parse_parametrize_args` in
`src/_pytest/mark/structures.py`. When a string argnames splits into exactly
one name the code sets force_tuple=True, which makes every argvalue be wrapped
as a *single* parameter value. A comma-terminated string like "arg," splits
into one name too, but a trailing comma is the string form of writing a
one-element tuple ("arg," == ("arg",)), so its argvalues are a list of
one-element tuples that must be UNPACKED, not wrapped.

The fix: only force tuple-wrapping when the single name is NOT written with a
trailing comma.
"""

import sys

PATH = "/app/src/src/_pytest/mark/structures.py"

BUGGY = (
    "        if isinstance(argnames, str):\n"
    "            argnames = [x.strip() for x in argnames.split(\",\") if x.strip()]\n"
    "            force_tuple = len(argnames) == 1\n"
    "        else:\n"
)
FIXED = (
    "        if isinstance(argnames, str):\n"
    "            # A trailing comma marks the tuple-style form: \"arg,\" must\n"
    "            # behave exactly like (\"arg\",) and unpack tuple values.\n"
    "            has_trailing_comma = argnames.rstrip().endswith(\",\")\n"
    "            argnames = [x.strip() for x in argnames.split(\",\") if x.strip()]\n"
    "            force_tuple = len(argnames) == 1 and not has_trailing_comma\n"
    "        else:\n"
)


def main() -> int:
    with open(PATH) as f:
        src = f.read()
    if "has_trailing_comma" in src:
        print("fix already applied, leaving the tree alone")
        return 0
    if BUGGY not in src:
        print(
            "ERROR: could not locate the buggy code; refusing to touch the tree",
            file=sys.stderr,
        )
        return 1
    src = src.replace(BUGGY, FIXED, 1)
    with open(PATH, "w") as f:
        f.write(src)
    print("fixed", PATH)
    return 0


if __name__ == "__main__":
    sys.exit(main())
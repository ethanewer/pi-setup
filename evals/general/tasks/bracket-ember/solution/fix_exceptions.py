#!/usr/bin/env python3
"""Apply the upstream pickling fix to requests' exceptions.py.

requests.exceptions.JSONDecodeError multiple-inherits from InvalidJSONError
(a RequestException, itself an IOError) and the stdlib json.JSONDecodeError.
Pickle walks the MRO and finds __reduce__ on IOError first, which
reconstructs the object from a single message argument, dropping the doc and
pos constructor arguments. Unpickling then raises

    TypeError: JSONDecodeError.__init__() missing 2 required positional
    arguments: 'doc' and 'pos'

Adding an explicit __reduce__ on requests.exceptions.JSONDecodeError that
delegates to the json library's JSONDecodeError.__reduce__ carries all three
constructor arguments through the pickle bytes, so the round-trip works and
the repr (and msg/doc/pos attributes) are preserved.

Idempotent; exits non-zero if the expected source snippets are not present
and applied.
"""

import sys
from pathlib import Path

METHOD = (
    "    def __reduce__(self):\n"
    "        \"\"\"\n"
    "        The __reduce__ method called when pickling the object must\n"
    "        be the one from the JSONDecodeError (be it json/simplejson)\n"
    "        as it expects all the arguments for instantiation, not just\n"
    "        one like the IOError, and the MRO would by default call the\n"
    "        __reduce__ method from the IOError due to the inheritance order.\n"
    "        \"\"\"\n"
    "        return CompatJSONDecodeError.__reduce__(self)\n"
)

ANCHOR = (
    "        CompatJSONDecodeError.__init__(self, *args)\n"
    "        InvalidJSONError.__init__(self, *self.args, **kwargs)\n"
)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: fix_exceptions.py PATH", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    src = path.read_text(encoding="utf-8")

    if "return CompatJSONDecodeError.__reduce__(self)" in src:
        print(f"{path} already carries the __reduce__ delegation")
        return 0

    if ANCHOR not in src:
        print("FATAL: expected JSONDecodeError.__init__ block not found:", file=sys.stderr)
        print(ANCHOR, file=sys.stderr)
        return 1

    src = src.replace(ANCHOR, ANCHOR + "\n" + METHOD, 1)
    path.write_text(src, encoding="utf-8")
    print(f"ok: added __reduce__ delegation to {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
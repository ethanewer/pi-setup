#!/usr/bin/env python3
"""Apply the FuncParamType ValueError-message fix to click's types.py.

The parent commit's FuncParamType.convert catches a ValueError raised by the
wrapped conversion function and echoes the raw input value back in
self.fail(value, ...), discarding the exception's message.  The fix uses
str(exc) as the message and falls back to the raw value only when the
exception's message is empty.  Idempotent; exits non-zero if the expected
snippets are not all present/applied.
"""

import sys
from pathlib import Path

OLD = """        try:
            return self.func(value)
        except ValueError:
            try:
                value = str(value)
            except UnicodeError:
                value = value.decode("utf-8", "replace")

            self.fail(value, param, ctx)"""

NEW = """        try:
            return self.func(value)
        except ValueError as exc:
            message = str(exc)

            if not message:
                try:
                    message = str(value)
                except UnicodeError:
                    message = value.decode("utf-8", "replace")

            self.fail(message, param, ctx)"""


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: fix_func_param_type.py PATH", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    src = path.read_text(encoding="utf-8")

    if NEW in src:
        print("types.py already carries the ValueError-message fix")
        return 0
    if OLD not in src:
        print("FAIL: expected FuncParamType.convert block not found; "
              "cannot apply fix", file=sys.stderr)
        return 1

    path.write_text(src.replace(OLD, NEW), encoding="utf-8")

    again = path.read_text(encoding="utf-8")
    if NEW not in again:
        print("FAIL: fix did not apply", file=sys.stderr)
        return 1
    print("applied FuncParamType ValueError-message fix to", path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
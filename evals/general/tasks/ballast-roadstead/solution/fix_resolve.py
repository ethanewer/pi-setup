#!/usr/bin/env python3
"""Apply the debug-resolve marker fix to a poetry checkout.

The bug: DebugResolveCommand builds each result row as a two-element list
``[name, version]`` and then, for any package whose environment marker is
not "any", executes ``row[2] = str(pkg.marker)`` -- an assignment past the
end of a two-element list, which raises ``IndexError: list assignment index
out of range``. The correct way to add the marker as a third column is
``row.append(str(pkg.marker))``.

Usage: python3 fix_resolve.py [repo-root]
Requires exactly one occurrence of the defective assignment; fails otherwise.
"""
from __future__ import annotations

import sys
from pathlib import Path

BAD = "row[2] = str(pkg.marker)"
GOOD = "row.append(str(pkg.marker))"


def main() -> int:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("/app/src")
    target = root / "src/poetry/console/commands/debug/resolve.py"
    text = target.read_text(encoding="utf-8")
    if text.count(BAD) != 1:
        print(
            f"expected exactly one occurrence of {BAD!r}, found {text.count(BAD)}",
            file=sys.stderr,
        )
        return 1
    if GOOD in text:
        print("fix already present", file=sys.stderr)
        return 0
    text = text.replace(BAD, GOOD)
    target.write_text(text, encoding="utf-8")
    print(f"wrote {target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
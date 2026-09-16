#!/usr/bin/env python3
"""Apply the upstream fix for the empty-subprocess-arg-list crash.

The checked-out injection-shell plugin guards the list-argument element access
with ``if isinstance(node, ast.List):`` and then indexes ``node.elts[0]``,
which raises IndexError when the argument is an empty list; bandit catches
the exception and logs the "Bandit internal error ... list index out of range"
line the task is about. The repaired guard additionally requires a non-empty
list, exactly matching upstream commit 049eba0 (issue #1141 / PR #1146).

Usage: fix_injection_shell.py [path-to-injection_shell.py]
"""
import sys
from pathlib import Path

DEFAULT = "/app/src/bandit/plugins/injection_shell.py"

OLD = "            if isinstance(node, ast.List):\n"
NEW = "            if isinstance(node, ast.List) and node.elts:\n"


def main() -> int:
    path = Path(sys.argv[1] if len(sys.argv) > 1 else DEFAULT)
    src = path.read_text()
    if src.count(OLD) != 1:
        print(
            f"error: expected the buggy guard to appear exactly once in {path}; found {src.count(OLD)}",
            file=sys.stderr,
        )
        return 1
    if NEW in src:
        print(f"{path} already contains the fix; nothing to do")
        return 0
    path.write_text(src.replace(OLD, NEW))
    print(f"fixed {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
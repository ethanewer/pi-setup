#!/usr/bin/env python3
"""Oracle helper: fix the empty-tuple type-args crash in /app/src.

The upstream fix adds a non-empty guard on the subscript slice before the
redundant-default-type-args suggestion is built, so an empty tuple subscript
never reaches ``node.slice.elts[0]``.
"""

from pathlib import Path

TARGET = Path("/app/src/pylint/extensions/typing.py")

OLD = (
    "            and isinstance(node.slice, nodes.Tuple)\n"
    "            and all("
)
NEW = (
    "            and isinstance(node.slice, nodes.Tuple)\n"
    "            and node.slice.elts\n"
    "            and all("
)


def main() -> None:
    src = TARGET.read_text()
    if NEW in src:
        print("fix already present")
        return
    if OLD not in src:
        raise SystemExit("unexpected source shape at %s; cannot apply fix" % TARGET)
    TARGET.write_text(src.replace(OLD, NEW, 1))
    print("fix applied to %s" % TARGET)


if __name__ == "__main__":
    main()
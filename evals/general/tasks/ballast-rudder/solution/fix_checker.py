#!/usr/bin/env python3
"""Apply the multi-assignment overload reinference fix to mypy/checker.py.

The bug: when the rvalue of a multiple assignment (`a, b = f(...)`) is a call
to an overloaded function and the assignment-target context makes the type
checker re-infer the callee's return type, the re-inferred type can come from a
different overload whose return type is not a fixed-length tuple
(e.g. a homogeneous `tuple[Any, ...]` instance or a plain non-tuple type).
The checked-out code then asserts unconditionally that the re-inferred type is
a fixed-length tuple, which aborts the whole type-check run with INTERNAL
ERROR. The fix keeps the originally inferred tuple type and only narrows to
the re-inferred one when it really is a fixed-length tuple.

This is a small, surgical edit of the single faulty block. The old block must
be present exactly once, and the replacement must be idempotent.
"""

import sys


OLD = (
    "                assert isinstance(reinferred_rvalue_type, TupleType)\n"
    "                rvalue_type = reinferred_rvalue_type\n"
)

NEW = (
    "                if isinstance(reinferred_rvalue_type, TupleType):\n"
    "                    # Contextual re-inference can select a different overload\n"
    "                    # whose return type is not a fixed-length tuple; keep the\n"
    "                    # originally inferred tuple type in that case.\n"
    "                    rvalue_type = reinferred_rvalue_type\n"
)


def main() -> int:
    path = sys.argv[1] if len(sys.argv) > 1 else "mypy/checker.py"
    with open(path, "r", encoding="utf-8") as fh:
        src = fh.read()

    if NEW in src:
        # Already fixed.
        return 0

    count = src.count(OLD)
    if count != 1:
        print(f"expected exactly one occurrence of the buggy block, found {count}",
              file=sys.stderr)
        return 1

    with open(path, "w", encoding="utf-8") as fh:
        fh.write(src.replace(OLD, NEW))
    print(f"patched {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
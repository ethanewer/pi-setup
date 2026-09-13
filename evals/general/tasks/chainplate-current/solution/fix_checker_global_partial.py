#!/usr/bin/env python3
"""Apply the minimal upstream fix for the chainplate-current bug.

In TypeChecker.visit_global_decl(), with --allow-redefinition enabled, mypy
adds each global name to the binder so its type can be widened by later
redefinitions. It propagated the *current* Var type unconditionally, which is
still a PartialType (e.g. the one created by `x = []`) for unannotated
module-level collection assignments, and PartialType must never reach
binder.assign_type() -- its is_subtype() path asserts on it, aborting the
whole run with an INTERNAL ERROR when the function body merely touches the
name. The fix resolves the *declaration* type via binder.get_declaration(),
which returns None exactly when the declaration is a partial type (the type
has not been pinned yet), and only then feeds the binder: a name with no
pinned declaration type simply has nothing to widen, so there is nothing to
assign.

Usage: fix_checker_global_partial.py /app/src/mypy/checker.py
"""
import sys

BUGGY = """                    self.binder.assign_type(n, sym.node.type, sym.node.type)"""

FIXED = """                    typ = get_declaration(n)
                    if typ is not None:
                        self.binder.assign_type(n, typ, typ)"""


def main() -> int:
    path = sys.argv[1] if len(sys.argv) > 1 else "/app/src/mypy/checker.py"
    with open(path) as f:
        text = f.read()
    if FIXED in text:
        print(f"ok: {path} already carries the fix")
        return 0
    count = text.count(BUGGY)
    if count != 1:
        print(f"FAIL: expected exactly one occurrence of the buggy line, found {count}")
        return 1
    text = text.replace(BUGGY, FIXED)
    with open(path, "w") as f:
        f.write(text)
    print(f"ok: applied the fix to {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
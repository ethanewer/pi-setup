#!/usr/bin/env python3
"""Repair mypy's Type[T] constructor-callee analysis (task painter-ebb).

The bug: when a TypeVar T is bounded by a union of classes, ``analyze_type_type_callee``
builds a *union* of constructor callables for the upper bound, but the ret-type
substitution that replaces each constructor's return type with the TypeVar instance
only handled plain callables and overloads.  A UnionType callee fell through with its
item return types (the individual classes) intact, so every constructor call through
a ``Type[T]`` parameter was checked against ``A | B`` instead of ``T`` and factory
functions were littered with spurious "Incompatible return value type" errors.

The repair factors the substitution into a helper that recurses into union items
(after get_proper_type / relevant_items), mirroring how the union is built.
"""
from __future__ import annotations

import sys

PATH = "/app/src/mypy/checkexpr.py"

BUGGY = """            callee = self.analyze_type_type_callee(get_proper_type(item.upper_bound), context)
            callee = get_proper_type(callee)
            if isinstance(callee, CallableType):
                callee = callee.copy_modified(ret_type=item)
            elif isinstance(callee, Overloaded):
                callee = Overloaded([c.copy_modified(ret_type=item) for c in callee.items])
            return callee
"""

FIXED = """            callee = self.analyze_type_type_callee(get_proper_type(item.upper_bound), context)
            return self._replace_type_type_callee_ret_type(callee, item)
"""

HELPER = (
    "\n"
    "    def _replace_type_type_callee_ret_type(self, callee: Type, ret_type: Type) -> Type:\n"
    "        'Rewrite the return type of every constructor branch of a Type[...] callee.'\n"
    "\n"
    "        # When a TypeVar is bounded by a union of classes, the callee for\n"
    "        # Type[item] is itself a union of constructors.  Each branch's return\n"
    "        # type must be replaced with the TypeVar instance, or calls through the\n"
    "        # type object are checked against the union of classes instead of T.\n"
    "        callee = get_proper_type(callee)\n"
    "        if isinstance(callee, CallableType):\n"
    "            return callee.copy_modified(ret_type=ret_type)\n"
    "        if isinstance(callee, Overloaded):\n"
    "            return Overloaded([c.copy_modified(ret_type=ret_type) for c in callee.items])\n"
    "        if isinstance(callee, UnionType):\n"
    "            return UnionType(\n"
    "                [\n"
    "                    self._replace_type_type_callee_ret_type(item, ret_type)\n"
    "                    for item in callee.relevant_items()\n"
    "                ],\n"
    "                line=callee.line,\n"
    "                column=callee.column,\n"
    "            )\n"
    "        return callee\n"
    "\n"
)

ANCHOR = "    def infer_arg_types_in_empty_context(self, args: list[Expression]) -> list[Type]:\n"


def main() -> int:
    with open(PATH, encoding="utf-8") as fh:
        src = fh.read()
    if BUGGY not in src:
        print("fix: buggy ret-type substitution block not found; already fixed?", file=sys.stderr)
        return 1
    if src.count(BUGGY) != 1:
        print("fix: ambiguous match for the buggy block", file=sys.stderr)
        return 1
    src = src.replace(BUGGY, FIXED)
    if ANCHOR not in src or "def _replace_type_type_callee_ret_type" in src:
        print("fix: anchor point for the helper method missing or already applied", file=sys.stderr)
        return 1
    src = src.replace(ANCHOR, HELPER + ANCHOR, 1)
    with open(PATH, "w", encoding="utf-8") as fh:
        fh.write(src)
    print("fix: checkexpr.py repaired (ret-type substitution recurses into unions)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
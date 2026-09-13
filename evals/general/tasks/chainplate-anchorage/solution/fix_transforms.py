#!/usr/bin/env python3
"""Apply the minimal upstream fix for matplotlib issue #28383.

Two changes in lib/matplotlib/transforms.py:

1. Transform.contains_branch_seperately (the base implementation, used by
   every non-blended, non-composite transform) returned a two-element LIST
   built from the whole-transform answer:

       return [self.contains_branch(other_transform)] * 2

   The documented return type is a pair of booleans; the fix returns the
   same two booleans as a tuple.

2. CompositeGenericTransform had no contains_branch_seperately override, so
   it fell back to that base implementation and answered BOTH axes with the
   same whole-composite "contains" result. For a composite whose right-hand
   component is a blended (per-axis) transform this is wrong: the per-axis
   question must be answered by the right-hand component, which knows each
   axis separately. The fix adds an override that answers (True, True) for
   the transform itself and otherwise delegates to the right-hand component
   (self._b).
"""
import sys

path = sys.argv[1]
src = open(path, encoding="utf-8").read()

# --- edit 1: base class returns a tuple of bools, not a list -------------
old_base = "        return [self.contains_branch(other_transform)] * 2\n"
new_base = "        return (self.contains_branch(other_transform), ) * 2\n"
assert src.count(old_base) == 1, "base list return not found exactly once in %s" % path
assert new_base not in src, "base fix already applied"
src = src.replace(old_base, new_base)

# --- edit 2: CompositeGenericTransform per-axis override -----------------
anchor = "    depth = property(lambda self: self._a.depth + self._b.depth)\n"
override = (
    "    def contains_branch_seperately(self, other_transform):\n"
    "        # docstring inherited\n"
    "        if self.output_dims != 2:\n"
    "            raise ValueError('contains_branch_seperately only supports '\n"
    "                             'transforms with 2 output dimensions')\n"
    "        if self == other_transform:\n"
    "            return (True, True)\n"
    "        return self._b.contains_branch_seperately(other_transform)\n"
    "\n"
)
assert src.count(anchor) == 1, "CompositeGenericTransform anchor not found exactly once"
assert "return self._b.contains_branch_seperately(other_transform)" not in src, \
    "composite override already present"
src = src.replace(anchor, override + anchor, 1)

open(path, "w", encoding="utf-8").write(src)
print("patched %s" % path)
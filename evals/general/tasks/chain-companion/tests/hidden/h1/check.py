#!/usr/bin/env python3
"""Hidden case h1: escaped open AND close parentheses as nested leaves.

On the pre-fix parser this input silently mis-parses (the escaped brackets
are treated as structure, the tree is corrupted and never round-trips). The
upstream regression test never exercises escapes in BOTH positions inside
one nested structure.
"""
import sys

from nltk.tree import Tree

src = open(sys.argv[1]).read()
tree = Tree.fromstring(src)
assert tree.label() == "ROOT", tree.label()
assert len(tree) == 3, len(tree)
assert tree[0].label() == "L1" and tree[1].label() == "L2" and tree[2].label() == "L3"
assert tree.leaves() == [r"\(", r"x\)", "ok"], tree.leaves()
assert str(tree) == src, (repr(str(tree)), repr(src))
assert Tree.fromstring(str(tree)) == tree
assert tree[0][0] == r"\(" and tree[1][0] == r"x\)"
print("hidden h1 OK")
#!/usr/bin/env python3
"""Hidden case h2: escaped brackets with a CUSTOM bracket pair.

The same tokenisation defect is reachable with brackets="[]"; the upstream
regression test only ever uses the default "()" pair. This input parses as
(ROOT (A \]) (B \[x) y): the escaped '\]' and '\[x' are literal leaves of A
and B respectively, and the final 'y' closes at the root. On the pre-fix
parser every such input raises ValueError.
"""
import sys

from nltk.tree import Tree

src = open(sys.argv[1]).read()
tree = Tree.fromstring(src, brackets="[]")
assert tree.label() == "ROOT", tree.label()
assert len(tree) == 3, len(tree)
assert tree[0].label() == "A" and tree[1].label() == "B"
assert tree[0].leaves() == [r"\]"], tree[0].leaves()
assert tree[1].leaves() == [r"\[x"], tree[1].leaves()
assert tree[2] == "y", repr(tree[2])
assert tree.leaves() == [r"\]", r"\[x", "y"], tree.leaves()
# str() always serialises with the default "()" pair; re-parsing that
# serialisation with the default pair must reproduce the same tree.
assert str(tree) == r"(ROOT (A \]) (B \[x) y)", str(tree)
assert Tree.fromstring(str(tree)) == tree
print("hidden h2 OK")
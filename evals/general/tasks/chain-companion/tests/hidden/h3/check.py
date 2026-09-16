#!/usr/bin/env python3
"""Hidden case h3: an escaped open+close pair glued into ONE leaf, next to
an escaped close-paren leaf (smiley), inside nesting.

The upstream regression test never combines an escaped pair inside a leaf
with a second escaped-bracket leaf in a deeper tree. On the pre-fix parser
this raises ValueError.
"""
import sys

from nltk.tree import Tree

src = open(sys.argv[1]).read()
tree = Tree.fromstring(src)
assert tree.label() == "S", tree.label()
assert len(tree) == 2, len(tree)
assert tree[0].label() == "GRP" and tree[1].label() == "EMOJI"
assert tree.leaves() == [r"\(q\)", r":\)"], tree.leaves()
assert str(tree) == src, (repr(str(tree)), repr(src))
assert Tree.fromstring(str(tree)) == tree
print("hidden h3 OK")
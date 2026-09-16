#!/usr/bin/env python3
"""Hidden case h4: an escaped close parenthesis in the MIDDLE of a leaf
(adjacent to regular text), nested under a second sibling.

The upstream regression test never places an escaped bracket adjacent to
ordinary token characters inside a deeper structure. On the pre-fix parser
this raises ValueError (the escaped ')' breaks the token stream).
"""
import sys

from nltk.tree import Tree

src = open(sys.argv[1]).read()
tree = Tree.fromstring(src)
assert tree.label() == "S", tree.label()
assert len(tree) == 2, len(tree)
assert tree[0].label() == "LOL" and tree[1].label() == "TXT"
assert tree.leaves() == [r"lol:p\)", "hi"], tree.leaves()
assert str(tree) == src, (repr(str(tree)), repr(src))
assert Tree.fromstring(str(tree)) == tree
print("hidden h4 OK")
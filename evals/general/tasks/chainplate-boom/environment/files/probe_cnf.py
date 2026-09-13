#!/usr/bin/env python3
"""Exploratory probe for the CNF conversion in the /app/src NLTK checkout.

chomsky_normal_form(tree, factor=...) must convert any parse tree in which an
internal node with more than two children has a plain terminal among its
children (a word, punctuation such as '+', or a non-string value such as the
integer 7), for both factor directions.  Every node of the result must have
at most two children, and un_chomsky_normal_form must recover the exact
original tree.  In this checkout the conversion crashes with an
AttributeError instead.  Exits non-zero while any case is broken, so scripts
can depend on the probe.
"""

import sys

from nltk.tree import Tree
from nltk.tree.transforms import chomsky_normal_form, un_chomsky_normal_form


def make_int_case():
    return Tree("S", [Tree("A", ["a"]), 7, Tree("B", ["b"]), Tree("C", ["c"])])


CASES = [
    ("terminal '+' among two subtrees (right)", lambda: Tree.fromstring("(S (S 1) + (S 2))"), "right"),
    ("terminal '+' among two subtrees (left)", lambda: Tree.fromstring("(S (S 1) + (S 2))"), "left"),
    ("int terminal among three subtrees (right)", make_int_case, "right"),
    ("int terminal among three subtrees (left)", make_int_case, "left"),
]


def main() -> int:
    failures = 0
    for label, factory, factor in CASES:
        tree = factory()
        expected = factory()
        try:
            chomsky_normal_form(tree, factor=factor)
        except Exception as e:  # noqa: BLE001 - the probe reports every outcome
            print(f"- {label}: raised {type(e).__name__}: {e}")
            failures += 1
            continue
        wide = [node for node in tree.subtrees() if len(node) > 2]
        try:
            un_chomsky_normal_form(tree)
            roundtrip = tree == expected
        except Exception as e:  # noqa: BLE001
            print(f"- {label}: un_chomsky_normal_form raised {type(e).__name__}: {e}")
            roundtrip = False
        ok = not wide and roundtrip
        print(
            f"- {label}: {'ok' if ok else 'BROKEN'}"
            f"{'' if ok else f' [nodes with >2 children: {len(wide)}, roundtrip: {roundtrip}]'}"
        )
        if not ok:
            failures += 1
    if failures:
        print(f"probe done: {failures} case(s) still broken")
        return 1
    print("probe done: all cases convert and round-trip")
    return 0


if __name__ == "__main__":
    sys.exit(main())
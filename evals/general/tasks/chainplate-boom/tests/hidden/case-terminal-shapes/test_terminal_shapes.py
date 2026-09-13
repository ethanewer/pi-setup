"""Hidden case for chainplate-boom: terminal SHAPES the upstream regression
tests do not use.

The upstream tests exercise a punctuation terminal ``+`` between two
subtrees and the integer ``7`` among three subtrees.  These cases drive the
same binarization code path with a float, a boolean, ``None``, multi-symbol
punctuation and characters that collide with the toolkit's own naming
conventions (``|`` is the marker used inside intermediate node names), for
both factorization directions, including a five-child node with two
terminals that forces several factorization steps.

Expected behaviour (the fixed upstream semantics, asserted through the
public API): chomsky_normal_form must not raise, every resulting node must
have at most two children, and un_chomsky_normal_form must recover the
original tree exactly -- compared by its printed form so terminal types are
not silently coerced.
"""

import pytest

from nltk.tree import Tree
from nltk.tree.transforms import chomsky_normal_form, un_chomsky_normal_form


def _check(factory, factor="right", **kwargs):
    tree = factory()
    expected = factory()
    chomsky_normal_form(tree, factor=factor, **kwargs)
    for subtree in tree.subtrees():
        assert len(subtree) <= 2, (factor, kwargs, subtree)
    un_chomsky_normal_form(tree)
    assert tree.pprint() == expected.pprint(), (factor, kwargs, tree.pprint(), expected.pprint())


def _two_subtrees_plus(term):
    return Tree("S", [Tree("A", ["a"]), term, Tree("B", ["b"])])


def _five_children_two_terminals():
    return Tree(
        "S",
        [
            Tree("NP", ["the", "cat"]),
            ",",
            Tree("VP", ["ran"]),
            Tree("PP", ["home"]),
            ".",
        ],
    )


def _three_subtrees_plus_float():
    return Tree("S", [Tree("A", ["a"]), 7.5, Tree("B", ["b"]), Tree("C", ["c"])])


def _four_subtrees_plus_int():
    return Tree("S", [Tree("A", ["a"]), 1000, Tree("B", ["b"]), Tree("C", ["c"]), Tree("D", ["d"])])


TERMINALS = [7.5, 0.5, True, False, None, "--", "...", "(", "|", ":"]


@pytest.mark.parametrize("term", TERMINALS)
@pytest.mark.parametrize("factor", ["right", "left"])
def test_two_subtrees_plus_assorted_terminal_roundtrips(term, factor):
    _check(lambda: _two_subtrees_plus(term), factor)


@pytest.mark.parametrize("factor", ["right", "left"])
def test_five_children_with_two_terminal_punctuation(factor):
    _check(_five_children_two_terminals, factor)


@pytest.mark.parametrize("factor", ["right", "left"])
def test_float_terminal_among_three_subtrees(factor):
    _check(_three_subtrees_plus_float, factor)


@pytest.mark.parametrize("factor", ["right", "left"])
def test_int_terminal_among_four_subtrees(factor):
    _check(_four_subtrees_plus_int, factor)
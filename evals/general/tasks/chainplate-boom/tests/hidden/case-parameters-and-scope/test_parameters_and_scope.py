"""Hidden case for chainplate-boom: parameter combinations and structural
scope the upstream regression tests do not use.

The upstream tests call chomsky_normal_form with default arguments only,
on one punctuation tree and one int tree.  These cases require the fix to
hold under horzMarkov truncation, vertMarkov parent annotation, terminals
nested at depth 2 inside a sibling that itself gets binarized, a terminal
sibling on a node that also has deep subtrees, and several independent
binarization sites in one input -- always with the exact round-trip
contract and with the terminal's own string carried into the intermediate
node names.
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


def _nested_terminal_at_depth_two():
    """Root binarizes with terminal '+' among siblings; its own VP child has
    three children including terminal 'it', so it binarizes too.  Two sites
    of the bug in one input, at different depths."""
    return Tree(
        "S",
        [
            Tree("VP", [Tree("V", ["saw"]), "it", Tree("PP", ["home"])]),
            "+",
            Tree("NP", ["mary"]),
            Tree("ADVP", ["then"]),
        ],
    )


def _six_children_deep_subtree():
    """A node with six children (three terminal-shaped, one deep subtree)."""
    return Tree(
        "S",
        [
            Tree("NP", ["the", "cat"]),
            ",",
            Tree("VP", [Tree("V", ["ran"]), "fast"]),
            Tree("PP", ["home"]),
            ".",
            Tree("ADVP", ["then"]),
        ],
    )


@pytest.mark.parametrize("factor", ["right", "left"])
@pytest.mark.parametrize(
    "kwargs",
    [
        {"horzMarkov": 1},
        {"vertMarkov": 2},
        {"horzMarkov": 2, "vertMarkov": 1},
    ],
)
def test_parameters_with_terminal_sibling_roundtrip(factor, kwargs):
    _check(lambda: _two_subtrees_plus("&"), factor, **kwargs)


@pytest.mark.parametrize("factor", ["right", "left"])
@pytest.mark.parametrize("kwargs", [{"horzMarkov": 1}, {"vertMarkov": 2}])
def test_parameters_on_five_child_node_roundtrip(factor, kwargs):
    _check(_five_children_two_terminals, factor, **kwargs)


@pytest.mark.parametrize("factor", ["right", "left"])
def test_nested_terminal_at_depth_two(factor):
    _check(_nested_terminal_at_depth_two, factor)


@pytest.mark.parametrize("factor", ["right", "left"])
def test_six_children_with_deep_subtree(factor):
    _check(_six_children_deep_subtree, factor)


@pytest.mark.parametrize("factor", ["right", "left"])
def test_terminal_string_is_carried_into_intermediate_node_names(factor):
    """The terminal's own value must be used where a subtree's label would be
    (the observable contract from the bug report): after conversion at least
    one intermediate node name must contain both the child-separator marker
    and the terminal's string."""
    tree = _two_subtrees_plus("--")
    chomsky_normal_form(tree, factor=factor)
    labels = {sub.label() for sub in tree.subtrees() if isinstance(sub, Tree)}
    assert any(("|" in label and "--" in label) for label in labels), (factor, labels)
    # and the whole thing still round-trips
    un_chomsky_normal_form(tree)
    assert tree.pprint() == _two_subtrees_plus("--").pprint()
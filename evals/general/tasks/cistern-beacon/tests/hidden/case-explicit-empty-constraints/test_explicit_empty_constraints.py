"""Hidden case for cistern-beacon: the no-constraints branch via EXPLICIT
empty constraint arguments.

The upstream regression test only omits the constraint matrices
(``A=None, b=None, A_eq=None, b_eq=None``).  This case drives the same branch
by passing explicitly empty ``A=[], b=[]`` / zero-row ``Matrix`` objects, and
their unbounded counterparts.  At the parent commit every one of these calls
dies with ``ValueError: must give A and B``; after the fix they must solve
exactly like the omitted forms.
"""

from sympy.matrices.dense import zeros
from sympy.solvers.simplex import UnboundedLPError, linprog
from sympy.testing.pytest import raises


def test_explicit_empty_inequalities():
    assert linprog([1], A=[], b=[]) == (0, [0])
    assert linprog([1, 1], A=[], b=[]) == (0, [0, 0])
    assert linprog([1, 1, 1], A=[], b=[]) == (0, [0, 0, 0])


def test_explicit_zero_row_matrices():
    assert linprog([1], A=zeros(0, 1), b=zeros(0, 1)) == (0, [0])
    assert linprog([1, 1], A=zeros(0, 2), b=zeros(0, 1)) == (0, [0, 0])


def test_explicit_empty_equalities_too():
    assert linprog([1], A=[], b=[], A_eq=zeros(0, 1), b_eq=zeros(0, 1)) == (0, [0])
    assert linprog([1, 1], A=zeros(0, 2), b=zeros(0, 1),
                   A_eq=zeros(0, 2), b_eq=zeros(0, 1)) == (0, [0, 0])


def test_explicit_empty_unbounded():
    raises(UnboundedLPError, lambda: linprog([-1], A=[], b=[]))
    raises(UnboundedLPError, lambda: linprog([-1, 1], A=[], b=[]))
    raises(UnboundedLPError, lambda: linprog([-1], A=zeros(0, 1), b=zeros(0, 1)))


def test_constrained_paths_untouched():
    # Guards: genuinely constrained calls must keep their exact current
    # semantics after the fix.
    assert linprog([1], [-1], [-1]) == (1, [1])
    assert linprog([2], [-1], [-1]) == (2, [1])
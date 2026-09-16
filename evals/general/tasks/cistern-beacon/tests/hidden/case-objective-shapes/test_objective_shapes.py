"""Hidden case for cistern-beacon: cost rows of other sizes and kinds, and
multi-variable default-bounds forms.

The upstream regression test uses 1- and 2-variable integer cost rows and a
single explicit ``bounds=(0, None)`` call.  This case exercises the same
unconstrained branch with larger cost rows, zero entries, non-integer
(Rational and Float) entries, and default-bounds forms over more than one
variable, plus their ``UnboundedLPError`` counterparts.  Every one of the
unconstrained calls crashes with ``ValueError: must give A and B`` at the
parent commit and must solve after the fix.
"""

from sympy.core.numbers import Float, Rational
from sympy.solvers.simplex import UnboundedLPError, linprog
from sympy.testing.pytest import raises


def test_larger_objective_rows():
    assert linprog([1, 1, 1]) == (0, [0, 0, 0])
    assert linprog([1, 0, 1, 0]) == (0, [0, 0, 0, 0])
    assert linprog([1, 2, 3, 4, 5]) == (0, [0, 0, 0, 0, 0])


def test_zero_entry_limits_unboundedness():
    # a lone negative entry is enough to make the unconstrained problem
    # unbounded below; zero entries elsewhere must not mask it
    raises(UnboundedLPError, lambda: linprog([0, -1]))
    raises(UnboundedLPError, lambda: linprog([1, 0, -2, 0]))


def test_rational_objective():
    assert linprog([Rational(1, 2), Rational(3, 4)]) == (0, [0, 0])
    raises(UnboundedLPError, lambda: linprog([Rational(-1, 2)]))


def test_float_objective():
    assert linprog([Float(1.5), Float(2.5)]) == (0, [0, 0])
    raises(UnboundedLPError, lambda: linprog([-0.5]))


def test_multi_variable_default_bounds():
    # explicit default bounds must keep flowing through the no-constraints
    # branch for more than one variable
    assert linprog([1, 1], bounds=(0, None)) == (0, [0, 0])
    assert linprog([1, 1, 1], bounds=(0, None)) == (0, [0, 0, 0])
    raises(UnboundedLPError, lambda: linprog([-1, 1], bounds=(0, None)))
    raises(UnboundedLPError, lambda: linprog([0, -1], bounds=(0, None)))
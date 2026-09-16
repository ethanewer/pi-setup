# Hidden case h3 for bitts-longshore: the multiplier is written as TWO
# factors (2*...*3) that sympy merges into one coefficient, and the inner
# modulus differs from the outer one - a structurally different input than
# the upstream regression test's single-coefficient form.
from sympy import Symbol, Mod


def test_nested_mod_agrees_with_merged_factors():
    t = Symbol('t')
    ti = Symbol('ti', integer=True)
    assert Mod(2*Mod(t, 4)*3, 9) == Mod(2*Mod(ti, 4)*3, 9).xreplace({ti: t})
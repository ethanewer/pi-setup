# Hidden case h2 for bitts-longshore: same defect, but triggered through the
# EVEN assumption (a stricter subtype of integer) rather than the plain
# integer assumption the upstream regression test uses.
from sympy import Symbol, Mod


def test_nested_mod_agrees_with_even_symbol():
    m = Symbol('m')
    mi = Symbol('mi', even=True)
    assert Mod(5*Mod(m, 6), 8) == Mod(5*Mod(mi, 6), 8).xreplace({mi: m})
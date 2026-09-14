# Hidden case h1 for bitts-longshore: nested modulo with a different
# coefficient, inner modulus and outer modulus than the upstream regression
# test uses (upstream: Mod(2*Mod(x0,3),5) and 8*Mod(floor(x1/64),4)).
from sympy import Symbol, Mod


def test_nested_mod_agrees_with_integer_symbol_varied_numbers():
    n = Symbol('n')
    ni = Symbol('ni', integer=True)
    assert Mod(3*Mod(n, 7), 11) == Mod(3*Mod(ni, 7), 11).xreplace({ni: n})
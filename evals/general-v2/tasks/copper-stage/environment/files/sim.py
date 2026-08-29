"""Resonance figure-of-merit for the copper-stage driver.

The model grades how close the reduced ratio a/(b+1) lands to the resonance
fraction R = 3.75 (= 15/4). A datum (a, b) in the search box contributes a
figure-of-merit in [.., 100.0]; higher is better. The figure is maximized when
|a/(b+1) - R| is as small as the integer box allows.

Stability note (the documented unstable step):
An earlier prototype produced the same figure with a 128-term alternating power
series in the residual. Near the resonance that series suffers catastrophic
cancellation and, for wide bounds, can push the argmax a few ulps off. The
public API below is the closed-form evaluation and is authoritative: use
`score()` and do not re-derive the residual with the fragile series, and do not
change the signature `score(a: int, b: int) -> float`.
"""

# Resonance fraction the design targets: 15/4.
RESONANCE = 15 / 4  # 3.75


def score(a: int, b: int) -> float:
    """Figure-of-merit for integer pair (a, b) with b >= 0 in practice.

    Deterministic, cheap, and stable in closed form. b+1 is always nonzero for
    the search boxes this driver hands out (every box has b >= 0).
    """
    r = a / (b + 1.0) - RESONANCE
    return 100.0 - 100.0 * abs(r)
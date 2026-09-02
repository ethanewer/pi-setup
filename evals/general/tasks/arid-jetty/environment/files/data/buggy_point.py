"""Taken directly from the trailing-development framework. This Point equates two
instances by value, BUT because it never defines __hash__, Python falls back to
the identity-based object.__hash__: two value-equal instances hash differently.
This violates the "equal objects hash equally" invariant.

Deliverable rule: a corrected Point must appear inside /app/solve.py (referenced
as solve.Point) whose __hash__ derives from the same value used by __eq__.
"""
class Point:
    def __init__(self, x, y):
        self.x = x
        self.y = y

    def __eq__(self, other):
        if not isinstance(other, Point):
            return NotImplemented
        return (self.x, self.y) == (other.x, other.y)

    # NOTE: no __hash__ override -> object identity hashing -> invariant broken.
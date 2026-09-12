"""Probe sympy's linprog on the unconstrained problem.

At the checked-out commit, linprog called with only a cost row and none of
the constraint matrices dies with a misleading ValueError deep inside the
solver.  On a tree where the bug is fixed, the same calls solve exactly:

    linprog([1])    -> (0, [0])
    linprog([1, 1]) -> (0, [0, 0])
    linprog([-1])   -> UnboundedLPError: Objective function can assume
                       arbitrarily large values!
"""

from sympy.solvers.simplex import linprog, UnboundedLPError


def show(label, fn):
    try:
        print(f"{label} -> {fn()!r}")
    except Exception as e:  # noqa: BLE001 - probe reports any failure mode
        print(f"{label} -> {type(e).__name__}: {e}")


if __name__ == "__main__":
    print("== linprog with only the cost row, no constraints ==")
    show("linprog([1])  ", lambda: linprog([1]))
    show("linprog([1, 1])", lambda: linprog([1, 1]))
    show("linprog([-1]) ", lambda: linprog([-1]))
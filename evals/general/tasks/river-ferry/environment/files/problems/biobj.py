"""problems/biobj.py — deterministic multi-objective test problems.

Every instance is derived from an integer seed only; calling these functions
is fully deterministic (no wall clock, no global RNG). All objectives are in
MINIMIZATION form: smaller is better, and the hypervolume/reference-point
definitions (see reference() / instruction.md) assume minimization boxes
[f, R].

Three problems are defined:

  knapsack  -> f1 = -total value, f2 = total weight   (bits, capacity bound)
  saddle    -> f1 = x0, f2 = g*(1 - (f1/g)^2)         (continuous, [0,1]^m)
  triplane  -> f1, f2, f3 = g - f1^2 - f2^2           (continuous 3-objective)

Their closed-form Pareto fronts are documented in /app/instruction.md (or the
task's instruction.md). The probe recomputes every objective independently
from these same formulas.
"""
import random


def knapsack(seed: int):
    """Bounded-knapsack instance: n items, values, weights, capacity.

    n = 20 + 4*(seed % 9) -> 20..52 items, so instance size varies with seed.
    objectives: (-value, weight); feasible iff weight <= capacity.
    reference point: (0, capacity)  (dominates every feasible point).
    """
    rng = random.Random(seed)
    n = 20 + 4 * (seed % 9)
    values = [rng.randrange(10, 101) for _ in range(n)]
    weights = [rng.randrange(5, 61) for _ in range(n)]
    capacity = int(0.45 * sum(weights))
    return {"problem": "knapsack", "n": n, "values": values,
            "weights": weights, "capacity": capacity,
            "reference": [0.0, float(capacity)]}


def saddle(seed: int):
    """Continuous problem with analytic Pareto front f2 = 1 - f1^2.

    x in [0,1]^m with m = 4 + (seed % 3). g(x) = 1 + 0.75*sum_{i>=1}(x_i-0.5)^2,
    f1 = x_0, f2 = g*(1 - (f1/g)^2). Minimum of g is 1 (all tail vars 0.5),
    so the Pareto front is {(t, 1-t^2) : t in [0,1]}. Any solution satisfies
    f1^2 + f2 >= 1, with equality exactly on the front.
    reference point: (1.0, 1 + 3*(m-1)/16) — dominates every feasible point.
    """
    m = 4 + (seed % 3)
    ref2 = 1.0 + 3.0 * (m - 1) / 16.0
    return {"problem": "saddle", "m": m, "reference": [1.0, ref2]}


def triplane(seed: int):
    """Three-objective problem whose Pareto front is the surface
    f3 = 1 - f1^2 - f2^2 over (f1, f2) in [0,1]^2.

    x in [0,1]^m with m = 5 + (seed % 3). g(x) = 1 + 0.75*sum_{i>=2}(x_i-0.5)^2,
    f1 = x_0, f2 = x_1, f3 = g - f1^2 - f2^2. Minimum of g is 1, hence:
    every feasible point satisfies f1^2 + f2^2 + f3 >= 1, with equality
    exactly on the Pareto front (the "front property").
    reference point: (1.0, 1.0, 1 + 3*(m-1)/16) — dominates every feasible point.
    """
    m = 5 + (seed % 3)
    ref3 = 1.0 + 3.0 * (m - 1) / 16.0
    return {"problem": "triplane", "m": m, "reference": [1.0, 1.0, ref3]}


def instance(problem: str, seed: int):
    return {"knapsack": knapsack, "saddle": saddle,
            "triplane": triplane}[problem](seed)


def evaluate(prob, sol):
    """Objective vector (minimization form) for a solution encoding."""
    p = prob["problem"]
    if p == "knapsack":
        assert len(sol) == prob["n"], "knapsack solution must have length n"
        value = sum(v for s, v in zip(sol, prob["values"]) if s)
        weight = sum(w for s, w in zip(sol, prob["weights"]) if s)
        return [-value, weight]
    if p == "saddle":
        assert len(sol) == prob["m"], "saddle solution must have length m"
        g = 1.0 + 0.75 * sum((x - 0.5) ** 2 for x in sol[1:])
        f1 = sol[0]
        f2 = g * (1.0 - (f1 / g) ** 2)
        return [f1, f2]
    if p == "triplane":
        assert len(sol) == prob["m"], "triplane solution must have length m"
        g = 1.0 + 0.75 * sum((x - 0.5) ** 2 for x in sol[2:])
        f1, f2 = sol[0], sol[1]
        f3 = g - f1 * f1 - f2 * f2
        return [f1, f2, f3]
    raise ValueError("unknown problem %r" % p)


def feasible(prob, sol):
    """True if the encoding is well-formed and satisfies the box/capacity
    constraints documented in instruction.md."""
    if prob["problem"] == "knapsack":
        if len(sol) != prob["n"]:
            return False
        return (all(s in (0, 1) for s in sol) and
                sum(w for s, w in zip(sol, prob["weights"]) if s) <= prob["capacity"])
    if len(sol) != prob["m"]:
        return False
    return all(0.0 <= x <= 1.0 for x in sol)
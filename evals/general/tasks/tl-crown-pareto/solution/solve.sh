#!/bin/bash
#
# tl-crown-pareto oracle. Does the real work: authors the NSGA-II CLI
# deliverable /app/nsga.py (a complete, deterministic, stdlib-only
# implementation with fast non-dominated sorting, crowding distance,
# tournament selection, crossover/mutation, feasibility repair, an external
# elitist archive and exact hypervolume), then smoke-runs it on the visible
# params to prove it works. Never reads /tests.
set -euo pipefail

cat > /app/nsga.py <<'PYEOF'
#!/usr/bin/env python3
"""nsga.py — NSGA-II for the multi-objective problems in problems/biobj.py.

CLI: python3 nsga.py <params.json> <result.json>

Reads a params file {"problem": "...", "pop": N, "generations": G,
"seed": S}, runs the documented NSGA-II scheme (fast non-dominated sorting,
crowding distance, binary tournament, elitist survival and an external
non-dominated archive) with a single random.Random(seed) stream, and writes
result.json with the final non-dominated front in canonical sorted order,
per-point crowding distances and the exact hypervolume of the front w.r.t.
the documented reference point.

Exit codes: 0 on success, 1 on any error, 2 on usage error.
Only the Python standard library is used; the run is fully deterministic.
"""

import json
import os
import random
import sys

_APP = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_APP, "problems"))
import biobj  # noqa: E402


# ---------------------------------------------------------------------------
# Parameters and problem plumbing
# ---------------------------------------------------------------------------

def load_params(path):
    with open(path, "r", encoding="utf-8") as fh:
        p = json.load(fh)
    for key in ("problem", "pop", "generations", "seed"):
        if key not in p:
            raise ValueError("params file missing key %r" % key)
    if not isinstance(p["problem"], str) or p["problem"] not in ("knapsack", "saddle", "triplane"):
        raise ValueError("bad problem id %r" % p["problem"])
    if not (isinstance(p["pop"], int) and p["pop"] >= 2):
        raise ValueError("pop must be an int >= 2")
    if not (isinstance(p["generations"], int) and p["generations"] >= 1):
        raise ValueError("generations must be an int >= 1")
    if not isinstance(p["seed"], int):
        raise ValueError("seed must be an int")
    return p


def random_solution(prob, rng):
    if prob["problem"] == "knapsack":
        return [rng.choice((0, 1)) for _ in range(prob["n"])]
    return [rng.random() for _ in range(prob["m"])]


def repair(prob, sol):
    """Greedy feasibility repair for the knapsack: while the selected weight
    exceeds capacity, drop the selected item with the smallest value/weight
    ratio (ties: smallest index). Continuous solutions are already feasible."""
    if prob["problem"] != "knapsack":
        return sol
    sol = list(sol)
    while True:
        weight = sum(w for s, w in zip(sol, prob["weights"]) if s)
        if weight <= prob["capacity"]:
            break
        cand = [(i, prob["values"][i] / prob["weights"][i])
                for i in range(prob["n"]) if sol[i]]
        i = min(cand, key=lambda t: (t[1], t[0]))[0]
        sol[i] = 0
    return sol


def evaluate(prob, sol):
    return biobj.evaluate(prob, sol)


# ---------------------------------------------------------------------------
# NSGA-II building blocks
# ---------------------------------------------------------------------------

def dominates(a, b, eps=1e-12):
    """True if objective tuple a weakly dominates b (minimization) and is
    strictly better in at least one objective."""
    better = False
    for x, y in zip(a, b):
        if x > y + eps:
            return False
        if x < y - eps:
            better = True
    return better


def nondominated_sort(pop):
    """Fast non-dominated sorting. pop: list of objective tuples.
    Returns fronts, each a list of indices (rank 0 first). Indices within a
    rank are ordered by objective tuple, then by index (documented tie-break)."""
    n = len(pop)
    dom_count = [0] * n
    dominated = [[] for _ in range(n)]
    fronts = [[]]
    for i in range(n):
        for j in range(i + 1, n):
            if dominates(pop[i], pop[j]):
                dominated[i].append(j)
                dom_count[j] += 1
            elif dominates(pop[j], pop[i]):
                dominated[j].append(i)
                dom_count[i] += 1
        if dom_count[i] == 0:
            fronts[0].append(i)
    k = 0
    while fronts[k]:
        nxt = []
        for i in fronts[k]:
            for j in dominated[i]:
                dom_count[j] -= 1
                if dom_count[j] == 0:
                    nxt.append(j)
        k += 1
        if nxt:
            fronts.append(nxt)
        else:
            break
    for f in fronts:
        f.sort(key=lambda i: (tuple(pop[i]), i))
    return fronts


def crowding_distances(pop, front):
    """Crowding distance per index within one rank. Boundary individuals get
    a large finite sentinel (1e9). Normalized per objective by (max-min);
    objectives with zero spread contribute 0."""
    dim = len(pop[0])
    dist = {i: 0.0 for i in front}
    for o in range(dim):
        order = sorted(front, key=lambda i: (pop[i][o], i))
        lo, hi = pop[order[0]][o], pop[order[-1]][o]
        spread = hi - lo
        if spread <= 0.0:
            continue
        dist[order[0]] = 1e9
        dist[order[-1]] = 1e9
        for t in range(1, len(order) - 1):
            i = order[t]
            dist[i] += (pop[order[t + 1]][o] - pop[order[t - 1]][o]) / spread
    return dist


def tournament_select(ranks, dists, rng):
    """Binary tournament on population indices. Lower rank wins; on equal
    rank the larger crowding distance wins; remaining ties go to the smaller
    index (documented tie-breaks)."""
    n = len(ranks)
    a = rng.randrange(n)
    b = rng.randrange(n)
    while b == a:
        b = rng.randrange(n)
    if ranks[a] != ranks[b]:
        return a if ranks[a] < ranks[b] else b
    if dists[a] != dists[b]:
        return a if dists[a] > dists[b] else b
    return a if a < b else b


def crossover(prob, p1, p2, rng):
    """Crossover with probability 0.9 (otherwise children are clones):
      - knapsack: single-point crossover at a random cut in [1, n)
      - continuous: uniform per-gene swap
    """
    n = len(p1)
    if rng.random() < 0.9:
        if prob["problem"] == "knapsack":
            cut = rng.randrange(1, n)
            c1 = p1[:cut] + p2[cut:]
            c2 = p2[:cut] + p1[cut:]
        else:
            c1 = [a if rng.random() < 0.5 else b for a, b in zip(p1, p2)]
            c2 = [b if rng.random() < 0.5 else a for a, b in zip(p1, p2)]
        return c1, c2
    return list(p1), list(p2)


def mutate(prob, sol, rng):
    """Per-gene mutation, all values clamped to the box [0,1]:
      - knapsack: bit-flip with probability 1/n
      - continuous: add a uniform [-0.2, 0.2] perturbation with probability
        1/(2n) (documented rate)
    """
    n = len(sol)
    out = list(sol)
    for i in range(n):
        if prob["problem"] == "knapsack":
            if rng.random() < 1.0 / n:
                out[i] = 1 - out[i]
        else:
            if rng.random() < 1.0 / (2 * n):
                out[i] = max(0.0, min(1.0, out[i] + rng.uniform(-0.2, 0.2)))
    return out


# ---------------------------------------------------------------------------
# Hypervolume (exact analytic union-of-boxes; minimization boxes [f, R])
# ---------------------------------------------------------------------------

def hypervolume(points, ref):
    """Hypervolume of the union of boxes [f_i, R] over the front points,
    exact for 2 and 3 objectives (no sampling, fully deterministic)."""
    dim = len(ref)
    pts = sorted({tuple(float(x) for x in p) for p in points})
    if not pts:
        return 0.0
    if dim == 2:
        return _hv2d(pts, ref)
    if dim == 3:
        return _hv3d(pts, ref)
    raise ValueError("hypervolume supports 2 or 3 objectives")


def _hv2d(pts, ref):
    rx, ry = ref
    pts = [(min(p[0], rx), min(p[1], ry)) for p in pts]
    pts = [p for p in pts if p[0] <= rx and p[1] <= ry]
    if not pts:
        return 0.0
    by_x = {}
    for p in pts:
        by_x.setdefault(p[0], []).append(p[1])
    xs = sorted(by_x)
    total = 0.0
    active_y = float("inf")
    for i, xa in enumerate(xs):
        active_y = min(active_y, min(by_x[xa]))
        xb = xs[i + 1] if i + 1 < len(xs) else rx
        if xb > xa:
            total += (xb - xa) * (ry - active_y)
    return total


def _hv3d(pts, ref):
    rx, ry, rz = ref
    pts = [(min(p[0], rx), min(p[1], ry), min(p[2], rz)) for p in pts]
    pts = [p for p in pts if p[0] <= rx and p[1] <= ry and p[2] <= rz]
    if not pts:
        return 0.0
    by_x = {}
    for p in pts:
        by_x.setdefault(p[0], []).append((p[1], p[2]))
    xs = sorted(by_x)
    total = 0.0
    cur = []
    for i, xa in enumerate(xs):
        cur.extend(by_x[xa])
        area = _hv2d(cur, (ry, rz))
        xb = xs[i + 1] if i + 1 < len(xs) else rx
        if xb > xa:
            total += (xb - xa) * area
    return total


# ---------------------------------------------------------------------------
# Evolutionary loop
# ---------------------------------------------------------------------------

def run_nsga2(prob, params):
    pop_size = params["pop"]
    generations = params["generations"]
    rng = random.Random(int(params["seed"]))
    archive_cap = 6 * pop_size

    # 1) initialization (documented draw order)
    pop = [repair(prob, random_solution(prob, rng)) for _ in range(pop_size)]
    objs = [evaluate(prob, s) for s in pop]
    archive = []  # external elitist archive: (index-in-archive, sol, objs)

    for _ in range(generations):
        # ranks and crowding distances of the current population
        fronts = nondominated_sort(objs)
        ranks = {}
        for r, f in enumerate(fronts):
            for i in f:
                ranks[i] = r
        dists = {}
        for f in fronts:
            dists.update(crowding_distances(objs, f))

        # mating pool: binary tournament selection
        pool = [tournament_select(ranks, dists, rng) for _ in range(pop_size)]

        # offspring: crossover pairs, mutation, feasibility repair
        children = []
        for k in range(0, pop_size, 2):
            p1 = pop[pool[k]]
            p2 = pop[pool[k + 1]]
            c1, c2 = crossover(prob, p1, p2, rng)
            children.append(repair(prob, mutate(prob, c1, rng)))
            children.append(repair(prob, mutate(prob, c2, rng)))
        objs_c = [evaluate(prob, s) for s in children]

        # elitist survival: sort P | Q, keep the best pop_size by rank, then
        # by descending crowding distance inside the overflowing rank
        combined = pop + children
        comb_objs = objs + objs_c
        F = nondominated_sort(comb_objs)
        new_pop = []
        for f in F:
            if len(new_pop) + len(f) <= pop_size:
                new_pop.extend(combined[i] for i in f)
                continue
            d = crowding_distances(comb_objs, f)
            order = sorted(f, key=lambda i: (-d.get(i, 0.0), i))
            new_pop.extend(combined[i] for i in order[: pop_size - len(new_pop)])
            break
        pop = new_pop
        objs = [evaluate(prob, s) for s in pop]

        # archive upddate: union the non-dominated members of the population
        # with the archive, drop now-dominated or duplicate members, and
        # truncate by crowding distance when the cap is exceeded
        front0 = nondominated_sort(objs)[0]
        archive.extend((pop[i], objs[i]) for i in front0)
        seen = {}
        for sol, o in archive:
            seen.setdefault(tuple(o), (sol, o))
        arch = list(seen.values())
        nd_i = nondominated_sort([o for _, o in arch])[0]
        archive = [arch[i] for i in nd_i]
        if len(archive) > archive_cap:
            d = crowding_distances([o for _, o in archive], list(range(len(archive))))
            order = sorted(range(len(archive)), key=lambda i: (-d.get(i, 0.0), i))
            order = order[:archive_cap]
            archive = [archive[i] for i in order]

    # result front = the archive (all non-dominated solutions ever found),
    # deduplicated by objectives and sorted lexicographically (canonical)
    front_objs = [tuple(o) for _, o in archive]
    order = sorted(range(len(archive)), key=lambda i: (front_objs[i], i))
    entries = []
    seen = set()
    for i in order:
        key = front_objs[i]
        if key in seen:
            continue
        seen.add(key)
        entries.append({
            "solution": [float(x) for x in archive[i][0]],
            "objectives": [float(x) for x in archive[i][1]],
        })

    ref = [float(x) for x in prob["reference"]]
    # crowding distances on the final archive front (canonical order)
    front_idx = list(range(len(entries)))
    front_pop = [e["objectives"] for e in entries]
    dists = crowding_distances(front_pop, front_idx)
    for j, e in enumerate(entries):
        e["crowding_distance"] = dists.get(j, 0.0)
    entries.sort(key=lambda e: tuple(e["objectives"]))

    return {
        "algorithm": "nsga2",
        "problem": prob["problem"],
        "params": {"problem": params["problem"], "pop": params["pop"],
                   "generations": params["generations"], "seed": params["seed"]},
        "reference": ref,
        "front": entries,
        "hypervolume": hypervolume([e["objectives"] for e in entries], ref),
    }


def main(argv):
    if len(argv) != 3:
        sys.stderr.write("usage: python3 nsga.py <params.json> <result.json>\n")
        return 2
    try:
        params = load_params(argv[1])
        prob = biobj.instance(params["problem"], params["seed"])
        result = run_nsga2(prob, params)
        with open(argv[2], "w", encoding="utf-8") as fh:
            json.dump(result, fh, indent=2)
            fh.write("\n")
    except Exception as exc:  # noqa: BLE001 - CLI contract: any error -> exit 1
        sys.stderr.write("nsga.py error: %s\n" % exc)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
PYEOF
chmod +x /app/nsga.py

# ---- Smoke test on the visible params: must produce a valid result file.
python3 /app/nsga.py /app/params.json /tmp/smoke_result.json
python3 - <<'PYEOF_SMOKE'
import json, sys
sys.path.insert(0, "/app/problems")
import biobj
with open("/tmp/smoke_result.json") as fh:
    res = json.load(fh)
assert res["algorithm"] == "nsga2"
assert res["problem"] == "knapsack"
params = json.load(open("/app/params.json"))
prob = biobj.instance(params["problem"], params["seed"])
for a, b in zip(res["reference"], prob["reference"]):
    assert abs(a - b) <= 1e-6
assert len(res["front"]) >= 5
for e in res["front"]:
    got = biobj.evaluate(prob, e["solution"])
    for a, b in zip(got, e["objectives"]):
        assert a == b
assert isinstance(res["hypervolume"], (int, float))
print("tl-crown-pareto oracle: /app/nsga.py written and smoke-run ok "
      "(front=%d, hv=%.1f)" % (len(res["front"]), res["hypervolume"]))
PYEOF_SMOKE

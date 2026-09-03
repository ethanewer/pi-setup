#!/usr/bin/env python3
"""Independent verifier probe for tl-crown-pareto.

Runs the deliverable /app/nsga.py against hidden params files and checks:

  (a) every returned solution is feasible and its objectives match an
      independent recompute from the encoding (exact for knapsack,
      rtol=1e-6/atol=1e-9 for continuous problems);
  (b) the returned front is truly non-dominated (minimization, eps 1e-7);
  (c) the reported hypervolume matches an independent exact computation of
      the union-of-boxes hypervolume w.r.t. the documented reference point;
  (d) quality gates:
        knapsack: HV(agent) >= 0.85 * HV(independent reference NSGA-II,
                                          same seed and budget)
        saddle:   IGD(agent, analytic front sample) < 0.9 * median IGD of
                  5 random-search fronts of identical evaluation budget
        triplane: documented front property mean(|f1^2+f2^2+f3 - 1|) <= 0.05,
                  max <= 0.25, front spans >= 0.6 in f1 and f2
  plus a static source check that the core NSGA-II components exist.

All reference computations are self-contained (independent re-implementation
of the documented formulas) and fully deterministic. Exits 0 only if every
case passes. Writes nothing; diagnostics to stderr.
"""
import json
import math
import os
import random
import subprocess
import sys

DELIVERABLE = "/app/nsga.py"
EPS = 1e-7

# ---------------------------------------------------------------------------
# Independent problem re-implementation (same formulas as /app/problems/biobj.py)
# ---------------------------------------------------------------------------

def make_problem(pid, seed):
    rng = random.Random(seed)
    if pid == "knapsack":
        n = 20 + 4 * (seed % 9)
        vals = [rng.randrange(10, 101) for _ in range(n)]
        wts = [rng.randrange(5, 61) for _ in range(n)]
        cap = int(0.45 * sum(wts))
        return {"kind": "knapsack", "n": n, "v": vals, "w": wts, "c": cap,
                "ref": [0.0, float(cap)]}
    if pid == "saddle":
        m = 4 + (seed % 3)
        return {"kind": "saddle", "m": m,
                "ref": [1.0, 1.0 + 3.0 * (m - 1) / 16.0]}
    if pid == "triplane":
        m = 5 + (seed % 3)
        return {"kind": "triplane", "m": m,
                "ref": [1.0, 1.0, 1.0 + 3.0 * (m - 1) / 16.0]}
    raise ValueError("unknown problem id %r" % pid)


def objective(prob, sol):
    k = prob["kind"]
    if k == "knapsack":
        val = sum(prob["v"][i] for i, s in enumerate(sol) if s)
        wt = sum(prob["w"][i] for i, s in enumerate(sol) if s)
        return [-val, wt]
    if k == "saddle":
        g = 1.0 + 0.75 * sum((x - 0.5) ** 2 for x in sol[1:])
        f1 = sol[0]
        return [f1, g * (1.0 - (f1 / g) ** 2)]
    if k == "triplane":
        g = 1.0 + 0.75 * sum((x - 0.5) ** 2 for x in sol[2:])
        return [sol[0], sol[1], g - sol[0] * sol[0] - sol[1] * sol[1]]
    raise ValueError(k)


def is_feasible(prob, sol):
    if prob["kind"] == "knapsack":
        if len(sol) != prob["n"]:
            return False
        if not all(s in (0, 1) for s in sol):
            return False
        return sum(prob["w"][i] for i, s in enumerate(sol) if s) <= prob["c"]
    return len(sol) == prob["m"] and all(0.0 <= x <= 1.0 for x in sol)


# ---------------------------------------------------------------------------
# Independent reference NSGA-II (used for the knapsack quality gate).
# Deterministic: identical seed -> identical archive front.
# ---------------------------------------------------------------------------

def ref_nsga2(prob, pop_size, generations, seed):
    rng = random.Random(seed)
    dim = prob["m"] if prob["kind"] != "knapsack" else prob["n"]

    def rand_sol():
        if prob["kind"] == "knapsack":
            return [rng.choice((0, 1)) for _ in range(dim)]
        return [rng.random() for _ in range(dim)]

    def repair(sol):
        if prob["kind"] != "knapsack":
            return sol
        s = list(sol)
        while sum(prob["w"][i] for i, b in enumerate(s) if b) > prob["c"]:
            cand = [(i, prob["v"][i] / prob["w"][i])
                    for i in range(prob["n"]) if s[i]]
            i = min(cand, key=lambda t: (t[1], t[0]))[0]
            s[i] = 0
        return s

    def dominates(a, b):
        better = False
        for x, y in zip(a, b):
            if x > y + 1e-12:
                return False
            if x < y - 1e-12:
                better = True
        return better

    def sort_ranks(pop):
        n = len(pop)
        cnt = [0] * n
        sl = [[] for _ in range(n)]
        fronts = [[]]
        for i in range(n):
            for j in range(i + 1, n):
                if dominates(pop[i], pop[j]):
                    sl[i].append(j)
                    cnt[j] += 1
                elif dominates(pop[j], pop[i]):
                    sl[j].append(i)
                    cnt[i] += 1
            if cnt[i] == 0:
                fronts[0].append(i)
        k = 0
        while fronts[k]:
            nxt = []
            for i in fronts[k]:
                for j in sl[i]:
                    cnt[j] -= 1
                    if cnt[j] == 0:
                        nxt.append(j)
            k += 1
            if nxt:
                fronts.append(nxt)
            else:
                break
        for f in fronts:
            f.sort(key=lambda i: (tuple(pop[i]), i))
        return fronts

    def crowding(pop, front):
        dist = {i: 0.0 for i in front}
        for o in range(len(pop[0])):
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

    def tournament(ranks, dists):
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

    def breed(p1, p2):
        if rng.random() < 0.9:
            if prob["kind"] == "knapsack":
                cut = rng.randrange(1, dim)
                return p1[:cut] + p2[cut:], p2[:cut] + p1[cut:]
            c1 = [a if rng.random() < 0.5 else b for a, b in zip(p1, p2)]
            c2 = [b if rng.random() < 0.5 else a for a, b in zip(p1, p2)]
            return c1, c2
        return list(p1), list(p2)

    def mutate(sol, rng_):
        out = list(sol)
        for i in range(dim):
            if prob["kind"] == "knapsack":
                if rng_.random() < 1.0 / dim:
                    out[i] = 1 - out[i]
            else:
                if rng_.random() < 1.0 / (2 * dim):
                    out[i] = max(0.0, min(1.0, out[i] + rng_.uniform(-0.2, 0.2)))
        return out

    pop = [repair(rand_sol()) for _ in range(pop_size)]
    objs = [objective(prob, s) for s in pop]
    archive = []
    for _ in range(generations):
        ranks = {}
        for r, f in enumerate(sort_ranks(objs)):
            for i in f:
                ranks[i] = r
        dists = {}
        for f in sort_ranks(objs):
            dists.update(crowding(objs, f))
        pool = [tournament(ranks, dists) for _ in range(pop_size)]
        kids = []
        for k in range(0, pop_size, 2):
            c1, c2 = breed(pop[pool[k]], pop[pool[k + 1]])
            kids.append(repair(mutate(c1, rng)))
            kids.append(repair(mutate(c2, rng)))
        objs_k = [objective(prob, s) for s in kids]
        comb = pop + kids
        comb_o = objs + objs_k
        F = sort_ranks(comb_o)
        newpop = []
        for f in F:
            if len(newpop) + len(f) <= pop_size:
                newpop.extend(comb[i] for i in f)
                continue
            d = crowding(comb_o, f)
            keep = sorted(f, key=lambda i: (-d.get(i, 0.0), i))
            newpop.extend(comb[i] for i in keep[:pop_size - len(newpop)])
            break
        pop = newpop
        objs = [objective(prob, s) for s in pop]
        front0 = sort_ranks(objs)[0]
        archive.extend((pop[i], objs[i]) for i in front0)
        seen = {}
        for sol, o in archive:
            seen.setdefault(tuple(o), (sol, o))
        arch = list(seen.values())
        nd = sort_ranks([o for _, o in arch])[0]
        archive = [arch[i] for i in nd]
        cap = 6 * pop_size
        if len(archive) > cap:
            d = crowding([o for _, o in archive], list(range(len(archive))))
            keep = sorted(range(len(archive)), key=lambda i: (-d.get(i, 0.0), i))
            archive = [archive[i] for i in keep[:cap]]
    return [o for _, o in archive]


# ---------------------------------------------------------------------------
# Exact hypervolume (union of minimization boxes [f, R]), 2 and 3 objectives
# ---------------------------------------------------------------------------

def _hv2d(pts, ref):
    rx, ry = ref
    pts = sorted({(min(p[0], rx), min(p[1], ry)) for p in pts})
    pts = [p for p in pts if p[0] <= rx and p[1] <= ry]
    if not pts:
        return 0.0
    by_x = {}
    for x, y in pts:
        by_x.setdefault(x, []).append(y)
    xs = sorted(by_x)
    total = 0.0
    active = float("inf")
    for i, xa in enumerate(xs):
        active = min(active, min(by_x[xa]))
        xb = xs[i + 1] if i + 1 < len(xs) else rx
        if xb > xa:
            total += (xb - xa) * (ry - active)
    return total


def _hv3d(pts, ref):
    rx, ry, rz = ref
    pts = sorted({(min(p[0], rx), min(p[1], ry), min(p[2], rz)) for p in pts})
    pts = [p for p in pts if p[0] <= rx and p[1] <= ry and p[2] <= rz]
    if not pts:
        return 0.0
    by_x = {}
    for x, y, z in pts:
        by_x.setdefault(x, []).append((y, z))
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


def hypervolume(points, ref):
    if len(ref) == 2:
        return _hv2d(points, ref)
    if len(ref) == 3:
        return _hv3d(points, ref)
    raise ValueError("unsupported dimension")


# ---------------------------------------------------------------------------
# Random-search baseline and IGD (saddle quality gate)
# ---------------------------------------------------------------------------

def igd(agent_pts, refset):
    """Inverted generational distance: mean over reference points of the
    Euclidean distance to the nearest agent front point."""
    if not agent_pts:
        return float("inf")
    total = 0.0
    for r in refset:
        best = min(sum((p[i] - r[i]) ** 2 for i in range(len(r))) for p in agent_pts)
        total += math.sqrt(best)
    return total / len(refset)


def saddle_reference_set():
    return [[i / 60.0, 1.0 - (i / 60.0) ** 2] for i in range(61)]


def nondom_subset(points):
    """Exact non-dominated subset of a point cloud (deduped). Fast skyline
    for 2 objectives; pairwise filter otherwise."""
    pts = sorted({tuple(p) for p in points})
    if not pts:
        return []
    if len(pts[0]) == 2:
        out = []
        best_y = float("inf")
        for p in pts:
            if p[1] < best_y:
                out.append(p)
                best_y = p[1]
        return out
    kept = []
    for p in pts:
        if not any(all(q[i] <= p[i] + 1e-12 for i in range(len(p)))
                   and any(q[i] < p[i] - 1e-12 for i in range(len(p)))
                   for q in kept):
            kept.append(p)
    return kept


def saddle_random_baseline(prob, pop_size, generations, seed, trials=5):
    """Median IGD of `trials` random-search fronts, each using the same
    evaluation budget pop_size*generations of uniform random samples."""
    budget = pop_size * generations
    refset = saddle_reference_set()
    igds = []
    for t in range(trials):
        rng = random.Random(202407 * 7 + seed + t)
        samples = []
        for _ in range(budget):
            dim = prob["m"]
            sol = [rng.random() for _ in range(dim)]
            if is_feasible(prob, sol):
                samples.append(objective(prob, sol))
        kept = nondom_subset(samples)
        igds.append(igd(kept, refset))
    igds.sort()
    return igds[len(igds) // 2]


# ---------------------------------------------------------------------------
# Static source check
# ---------------------------------------------------------------------------

CORE_TOKENS = ("crowd", "tourn", "cross", "mutat", "hypervol")


def check_source(path):
    """The deliverable must implement the core NSGA-II components
    (recognizable by their documented names). At least 4 of 5 must appear."""
    try:
        with open(path, "r", encoding="utf-8") as fh:
            src = fh.read().lower()
    except OSError as exc:
        return "unreadable: %s" % exc
    hits = sum(1 for tok in CORE_TOKENS if tok in src)
    if hits < 4:
        return "core NSGA-II components missing (found %d of %d: %s)" % (
            hits, len(CORE_TOKENS), CORE_TOKENS)
    return None


# ---------------------------------------------------------------------------
# Case checking
# ---------------------------------------------------------------------------

def run_deliverable(params_path, out_path):
    cmd = ["python3", DELIVERABLE, params_path, out_path]
    if os.path.exists(out_path):
        os.remove(out_path)
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    except Exception as exc:  # noqa: BLE001
        return None


def check_case(params_path):
    """Returns None on success, an error string otherwise."""
    try:
        with open(params_path) as fh:
            params = json.load(fh)
    except Exception as exc:  # noqa: BLE001
        return "hidden params unreadable: %s" % exc
    pid = params["problem"]
    pop_size = params["pop"]
    generations = params["generations"]
    seed = params["seed"]

    out_path = "/tmp/tl_crown_pareto_out.json"
    r = run_deliverable(params_path, out_path)
    if r is None:
        return "deliverable run timed out/crashed"
    if r.returncode != 0:
        return "deliverable exited %d: %s" % (r.returncode, (r.stderr or "").strip()[:200])
    try:
        with open(out_path) as fh:
            res = json.load(fh)
    except Exception as exc:  # noqa: BLE001
        return "result.json unreadable: %s" % exc

    # --- schema/meta
    if res.get("algorithm") != "nsga2":
        return "algorithm field != nsga2"
    if res.get("problem") != pid:
        return "problem field mismatch"
    for key, val in (("problem", pid), ("pop", pop_size),
                     ("generations", generations), ("seed", seed)):
        if res.get("params", {}).get(key) != val:
            return "params echo mismatch for %r" % key
    front = res.get("front")
    if not isinstance(front, list) or len(front) < 5:
        return "front missing/smaller than 5"
    ref = res.get("reference")
    if not isinstance(ref, list):
        return "reference missing"
    prob = make_problem(pid, seed)
    if len(ref) != len(prob["ref"]):
        return "reference dim mismatch"
    for a, b in zip(ref, prob["ref"]):
        if abs(a - b) > 1e-6:
            return "reference point differs from documented value"
    hv_reported = res.get("hypervolume")

    # --- (a) feasibility + objective recompute
    for e in front:
        sol = e.get("solution")
        ob = e.get("objectives")
        if not isinstance(sol, list) or not isinstance(ob, list):
            return "malformed front entry"
        if not is_feasible(prob, sol):
            return "infeasible solution returned"
        want = objective(prob, sol)
        for a, b in zip(ob, want):
            if abs(a - b) > 1e-6 * max(1.0, abs(b)) + 1e-9:
                return "objectives do not match recompute (%s vs %s)" % (ob, want)
        cd = e.get("crowding_distance")
        # Contract says: finite, >= 0 ("large finite sentinel" allowed, magnitude
        # unspecified) — only sanity-check those, not a magic upper bound.
        if (not isinstance(cd, (int, float)) or isinstance(cd, bool)
                or not math.isfinite(float(cd)) or cd < 0.0):
            return "crowding_distance out of range"

    # --- (b) mutual non-domination
    pts = [tuple(e["objectives"]) for e in front]
    if len(set(pts)) != len(pts):
        return "duplicate objective tuples in front"
    for i, a in enumerate(pts):
        for j, b in enumerate(pts):
            if i == j:
                continue
            better = False
            ok = True
            for x, y in zip(a, b):
                if x > y + EPS:
                    ok = False
                    break
                if x < y - EPS:
                    better = True
            if ok and better:
                return "front contains dominated point %s vs %s" % (a, b)

    # --- canonical order (ascending objective tuple)
    ordered = sorted(pts)
    if ordered != [tuple(e["objectives"]) for e in front]:
        return "front not in canonical (ascending objective) order"

    # --- (c) hypervolume consistency
    want_hv = hypervolume(pts, prob["ref"])
    if not isinstance(hv_reported, (int, float)):
        return "hypervolume missing"
    if abs(hv_reported - want_hv) > 1e-6 * max(1.0, abs(want_hv)):
        return "hypervolume %r != independent %r" % (hv_reported, want_hv)

    # --- (d) quality gates
    if pid == "knapsack":
        ref_front = ref_nsga2(prob, pop_size, generations, seed)
        ref_hv = hypervolume(ref_front, prob["ref"])
        if ref_hv <= 0:
            return "reference run produced empty front"
        if hv_reported < 0.85 * ref_hv:
            return ("hypervolume %r < 0.85x reference %r "
                    "(weak coverage / not a real multi-objective search)"
                    % (hv_reported, ref_hv))
    elif pid == "saddle":
        base = saddle_random_baseline(prob, pop_size, generations, seed)
        if base <= 0:
            return "baseline degenerate"
        agent_igd = igd(pts, saddle_reference_set())
        if not (agent_igd < 0.9 * base):
            return ("saddle IGD %.5f not below 0.9x random-search baseline "
                    "%.5f" % (agent_igd, base))
    elif pid == "triplane":
        sdevs = [abs(p[0] ** 2 + p[1] ** 2 + p[2] - 1.0) for p in pts]
        mean_s = sum(sdevs) / len(sdevs)
        max_s = max(sdevs)
        span1 = max(p[0] for p in pts) - min(p[0] for p in pts)
        span2 = max(p[1] for p in pts) - min(p[1] for p in pts)
        if mean_s > 0.05 or max_s > 0.25:
            return ("triplane front property violated: mean|S-1|=%.4f "
                    "max=%.4f" % (mean_s, max_s))
        if span1 < 0.6 or span2 < 0.6:
            return ("triplane front does not span [0,1]^2 (spans %.2f, %.2f)"
                    % (span1, span2))
    else:
        return "unsupported problem id %r" % pid
    return None


def main(argv):
    failures = []
    if len(argv) == 2 and argv[1] == "--check-source":
        err = check_source(DELIVERABLE)
        if err:
            failures.append("source check: %s" % err)
    else:
        cases_dir = argv[1] if len(argv) > 1 else "/tests/hidden/cases"
        paths = sorted(os.path.join(cases_dir, f) for f in os.listdir(cases_dir)
                       if f.endswith(".json"))
        if not paths:
            failures.append("no hidden case params found in %s" % cases_dir)
        for p in paths:
            err = check_case(p)
            if err:
                failures.append("%s: %s" % (os.path.basename(p), err))
    if failures:
        print("verify failures:", failures, file=sys.stderr)
        return 1
    print("tl-crown-pareto probe: all checks passed", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
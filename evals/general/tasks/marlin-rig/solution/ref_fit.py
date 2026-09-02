#!/usr/bin/env python3
"""Reference implementation for marlin-rig.

Feature matching over intensity-raster views plus a robust (exhaustive-RANSAC)
similarity-transform fit. Pure standard library.
"""
import json
import math
import os
import sys

PATCH = 5          # patch side (P x P), centered on the keypoint
RATIO = 0.8        # Lowe ratio threshold: best <= RATIO * second
HALF = PATCH // 2
EPS = 1e-9


def load_raster(path):
    with open(path, "r", encoding="utf-8") as fh:
        tokens = fh.read().split()
    it = iter(tokens)
    W = int(next(it))
    H = int(next(it))
    grid = []
    for y in range(H):
        grid.append([int(next(it)) for _ in range(W)])
    return W, H, grid


def load_json(path):
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def descriptors(W, H, grid, keypoints):
    """Return (list of unit descriptors, list of kept original indices).

    A keypoint is usable iff its full P x P patch lies inside the raster and
    the centered patch has non-zero norm.  Descriptor layout: row-major over
    the patch window (y from y0-HALF..y0+HALF, x from x0-HALF..x0+HALF).
    """
    desc = []
    kept = []
    skipped = 0
    for (x0, y0) in keypoints:
        x0 = int(x0)
        y0 = int(y0)
        if not (HALF <= x0 < W - HALF and HALF <= y0 < H - HALF):
            skipped += 1
            continue
        vals = [float(grid[y0 + dy][x0 + dx])
                for dy in range(-HALF, HALF + 1)
                for dx in range(-HALF, HALF + 1)]
        m = sum(vals) / float(PATCH * PATCH)
        c = [v - m for v in vals]
        nrm = math.sqrt(sum(v * v for v in c))
        if nrm < 1e-12:
            skipped += 1
            continue
        desc.append([v / nrm for v in c])
        kept.append((x0, y0))
    return desc, kept, skipped


def dist2(u, v):
    s = 0.0
    for a, b in zip(u, v):
        d = a - b
        s += d * d
    return s


def match(desc_a, desc_b):
    """Mutual-nearest + ratio-test matching.

    For each a-descriptor (in order): best = argmin distance (ties -> lowest
    b index), second = second-smallest distance over a DIFFERENT index.
    Accept a->best iff best <= RATIO * second (if only one b descriptor
    exists, accept).  Keep the pair only if b's plain argmin over a (ties ->
    lowest a index) is exactly a.  Output pairs in a order.
    """
    if not desc_a or not desc_b:
        return []
    nb = len(desc_b)
    # b -> plain argmin over a (ties -> lowest index)
    b_best = []
    for j in range(nb):
        bi = -1
        bd = None
        for i in range(len(desc_a)):
            d = dist2(desc_a[i], desc_b[j])
            if bd is None or d < bd:
                bd = d
                bi = i
        b_best.append(bi)
    matches = []
    for i, da in enumerate(desc_a):
        dists = [dist2(da, db) for db in desc_b]
        best_j = 0
        best_d = dists[0]
        second_d = None
        for j in range(1, nb):
            d = dists[j]
            if d < best_d:
                second_d = best_d
                best_d = d
                best_j = j
            elif second_d is None or d < second_d:
                second_d = d
        if nb > 1:
            if second_d is None:
                continue
            if not (best_d <= RATIO * second_d):
                continue
        if b_best[best_j] != i:
            continue
        matches.append((i, best_j))
    return matches


def apply_sim(a, b, tx, ty, x, y):
    # similarity transform as complex multiplication: (a + bi)(x + yi) + (tx + tyi)
    return (a * x - b * y + tx, b * x + a * y + ty)


def residual(params, p, q):
    a, b, tx, ty = params
    u, v = apply_sim(a, b, tx, ty, p[0], p[1])
    return math.hypot(u - q[0], v - q[1])


def model_from_pair(p1, q1, p2, q2):
    """Exact similarity transform mapping p1->q1, p2->q2 (complex division).

    Returns (a, b, tx, ty) or None when the source pair is degenerate.
    """
    dx = p2[0] - p1[0]
    dy = p2[1] - p1[1]
    if math.hypot(dx, dy) < EPS:
        return None
    # complex: (q2-q1) / (p2-p1)
    num_r = q2[0] - q1[0]
    num_i = q2[1] - q1[1]
    den = dx * dx + dy * dy
    m_r = (num_r * dx + num_i * dy) / den
    m_i = (num_i * dx - num_r * dy) / den
    a = m_r
    b = m_i
    tx = q1[0] - (a * p1[0] - b * p1[1])
    ty = q1[1] - (b * p1[0] + a * p1[1])
    return (a, b, tx, ty)


def fit_similarity(points):
    """Closed-form least-squares similarity (Umeyama, no reflection).

    points: list of (p, q). Returns (a, b, tx, ty). Requires >= 1 point
    with non-degenerate spread; falls back to the single-point translation
    when the spread is ~zero.
    """
    n = len(points)
    mx = sum(p[0] for p, _ in points) / n
    my = sum(p[1] for p, _ in points) / n
    mu = sum(q[0] for _, q in points) / n
    mv = sum(q[1] for _, q in points) / n
    sxx = sum((p[0] - mx) ** 2 + (p[1] - my) ** 2 for p, _ in points)
    if sxx < EPS:
        tx = mu - mx
        ty = mv - my
        return (1.0, 0.0, tx, ty)
    sxu = sum((p[0] - mx) * (q[0] - mu) + (p[1] - my) * (q[1] - mv)
              for p, q in points)
    syu = sum((p[0] - mx) * (q[1] - mv) - (p[1] - my) * (q[0] - mu)
              for p, q in points)
    a = sxu / sxx
    b = syu / sxx
    tx = mu - (a * mx - b * my)
    ty = mv - (b * mx + a * my)
    return (a, b, tx, ty)


def inlier_set(params, pairs, tau):
    return [i for i, (p, q) in enumerate(pairs)
            if residual(params, p, q) <= tau]


def robust_fit(pairs, tau):
    """Exhaustive 2-point RANSAC + iterative refinement.

    Returns (status, params, inlier_indices, residuals, rms).
    status is "ok" or "degenerate".
    """
    n = len(pairs)
    best = None  # (count, resid_sum, i, j, params)
    for i in range(n):
        for j in range(i + 1, n):
            p1, q1 = pairs[i]
            p2, q2 = pairs[j]
            params = model_from_pair(p1, q1, p2, q2)
            if params is None:
                continue
            idx = inlier_set(params, pairs, tau)
            cnt = len(idx)
            rsum = sum(residual(params, pairs[k][0], pairs[k][1]) for k in idx)
            cand = (-cnt, rsum, i, j)
            if best is None or cand < best[:4]:
                best = (-cnt, rsum, i, j, params)
    if best is None or -best[0] < 3:
        return ("degenerate", None, [], None, None)
    params = best[4]
    inliers = inlier_set(params, pairs, tau)
    for _ in range(10):
        if len(inliers) < 1:
            break
        new_params = fit_similarity([pairs[k] for k in inliers])
        new_inliers = inlier_set(new_params, pairs, tau)
        if new_inliers == inliers:
            params = new_params
            break
        inliers = new_inliers
        params = new_params
        if len(inliers) < 3:
            return ("degenerate", None, [], None, None)
    if len(inliers) < 3:
        return ("degenerate", None, [], None, None)
    residuals = [residual(params, p, q) for p, q in pairs]
    rms = math.sqrt(sum(residuals[k] ** 2 for k in inliers) / len(inliers))
    return ("ok", params, inliers, residuals, rms)


def run_scenario(scen_dir):
    scen = load_json(os.path.join(scen_dir, "scenario.json"))
    tau = float(scen["tau"])
    Wa, Ha, ga = load_raster(os.path.join(scen_dir, "view_a.txt"))
    Wb, Hb, gb = load_raster(os.path.join(scen_dir, "view_b.txt"))
    kpa = load_json(os.path.join(scen_dir, "keypoints_a.json"))
    kpb = load_json(os.path.join(scen_dir, "keypoints_b.json"))

    desc_a, kept_a, skip_a = descriptors(Wa, Ha, ga, kpa)
    desc_b, kept_b, skip_b = descriptors(Wb, Hb, gb, kpb)
    matches = match(desc_a, desc_b)
    pairs = [(kept_a[i], kept_b[j]) for (i, j) in matches]

    status, params, inliers, residuals, rms = robust_fit(pairs, tau)

    out = {
        "scenario": scen.get("name", os.path.basename(scen_dir)),
        "tau": tau,
        "n_keypoints_a": len(kpa),
        "n_keypoints_b": len(kpb),
        "n_skipped_a": skip_a,
        "n_skipped_b": skip_b,
        "n_matches": len(matches),
        "matches": [[i, j] for (i, j) in matches],
        "status": status,
        "params": None,
        "inliers": [],
        "n_inliers": 0,
        "rms_inlier": None,
        "residuals": None,
    }
    if status == "ok":
        a, b, tx, ty = params
        out["params"] = {
            "scale": math.hypot(a, b),
            "theta": math.atan2(b, a),
            "tx": tx,
            "ty": ty,
        }
        out["inliers"] = list(inliers)
        out["n_inliers"] = len(inliers)
        out["rms_inlier"] = rms
        out["residuals"] = residuals
    return out


def main():
    if len(sys.argv) != 3:
        print("usage: fit.py <scenario_dir> <out.json>", file=sys.stderr)
        return 2
    result = run_scenario(sys.argv[1])
    with open(sys.argv[2], "w", encoding="utf-8") as fh:
        json.dump(result, fh, indent=2)
    return 0


if __name__ == "__main__":
    sys.exit(main())

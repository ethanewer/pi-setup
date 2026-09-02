#!/usr/bin/env python3
"""
tests/refcheck.py — independent reference validator for granite-anchor.

Usage:
    python3 refcheck.py <config.json> <outdir>

Loads the config, computes the canonical BFS ground truth (distances by
breath-first-search, per-depth frontiers, depth counts, parent-search-tree
edges, and the shortest start->goal board path), then verifies that outdir
contains the five artifact types matching that ground truth exactly.

Prints nothing on success and exits 0; prints one explanation per problem on
stdout/stderr and exits 1. This helper lives under /tests and is only ever run
by test.sh; the agent never sees it.
"""
import sys, os, json, hashlib
from collections import deque


def ground_truth(cfg):
    start = int(cfg["start"])
    goal = int(cfg["goal"])
    nodes = {int(k): v["rows"] for k, v in cfg["nodes"].items()}
    edges = {int(k): list(v) for k, v in cfg.get("edges", {}).items()}

    dist = {start: 0}
    parent = {}
    dq = deque([start])
    while dq:
        u = dq.popleft()
        for v in sorted(edges.get(u, [])):
            if v not in nodes or v in dist:
                continue
            dist[v] = dist[u] + 1
            parent[v] = u
            dq.append(v)

    maxd = max(dist.values()) if dist else -1
    depth_counts = [sum(1 for n in dist if dist[n] == d) for d in range(maxd + 1)]
    frontiers = [sorted(n for n in dist if dist[n] == d) for d in range(maxd + 1)]
    dag = sorted((parent[v], v) for v in parent)

    if goal in dist:
        path = []
        cur = goal
        while True:
            path.append(cur)
            if cur == start:
                break
            cur = parent[cur]
        path.reverse()
    else:
        path = [start]
    boards = [nodes[p] for p in path]
    return maxd, depth_counts, frontiers, dag, boards


def report(msg):
    print("REFCHECK-FAIL: " + msg, file=sys.stderr)
    return False


def verify(cfg_path, outdir):
    with open(cfg_path) as f:
        cfg = json.load(f)
    start = int(cfg["start"])
    maxd, depth_counts, frontiers, dag, boards = ground_truth(cfg)
    ok = True

    # --- per-depth frontier files ---
    for d in range(maxd + 1):
        fname = "frontier_%d.txt" % d
        fp = os.path.join(outdir, fname)
        if not os.path.exists(fp):
            ok = report("missing " + fname); continue
        with open(fp) as f:
            got = f.read().splitlines()
        exp = list(map(str, frontiers[d]))
        if got != exp:
            ok = report("frontier_%d.txt = %r expected %r" % (d, got, exp))

    # --- checksum sidecar ---
    sha_path = os.path.join(outdir, "frontier.sha256")
    sha_lines = []
    if os.path.exists(sha_path):
        with open(sha_path) as f:
            sha_lines = [ln.strip() for ln in f if ln.strip()]
    for d in range(maxd + 1):
        fname = "frontier_%d.txt" % d
        fp = os.path.join(outdir, fname)
        want = "  " + fname
        entry = next((ln for ln in sha_lines if ln.endswith(want)), None)
        if entry is None:
            ok = report("frontier.sha256 missing entry for " + fname)
            continue
        h = entry.split()[0]
        with open(fp, "rb") as f:
            real = hashlib.sha256(f.read()).hexdigest()
        if h != real:
            ok = report("checksum for %s does not match file bytes" % fname)

    # --- depth summary ---
    ds = os.path.join(outdir, "depth_summary.txt")
    if os.path.exists(ds):
        got = [ln.strip() for ln in open(ds) if ln.rstrip("\n")]
    else:
        got = []
    exp_ds = ["depth,count"] + ["%d,%d" % (d, depth_counts[d]) for d in range(maxd + 1)]
    if got != exp_ds:
        ok = report("depth_summary.txt misleading; expected %r" % (exp_ds,))

    # --- dag edges ---
    de = os.path.join(outdir, "dag_edges.csv")
    if os.path.exists(de):
        got = [ln.strip() for ln in open(de) if ln.rstrip("\n")]
    else:
        got = []
    exp_de = ["from,to"] + ["%d,%d" % (a, b) for a, b in dag]
    if got != exp_de:
        ok = report("dag_edges.csv misleading; expected %r" % (exp_de,))

    # --- move trace ---
    mt = os.path.join(outdir, "move_trace.json")
    if os.path.exists(mt):
        try:
            data = json.load(open(mt))
            got_boards = data.get("boards")
        except Exception as e:
            ok = report("move_trace.json unparseable: %r" % (e,))
            got_boards = None
    else:
        got_boards = None
    if not (isinstance(got_boards, list) and len(got_boards) > 0):
        ok = report("move_trace.json must hold a non-empty boards list")
    elif got_boards != boards:
        ok = report("move_trace.json boards do not match the reference path")

    # --- starter row check on the trace ---
    start_rows = cfg["nodes"][str(start)]["rows"]
    if isinstance(got_boards, list) and got_boards and got_boards[0] != start_rows:
        ok = report("move_trace.json first board does not match the starter state")

    if ok:
        # cleanup any case-local scratch we do not want left around
        return True
    return False


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("usage: refcheck.py <config.json> <outdir>", file=sys.stderr)
        sys.exit(2)
    sys.exit(0 if verify(sys.argv[1], sys.argv[2]) else 1)
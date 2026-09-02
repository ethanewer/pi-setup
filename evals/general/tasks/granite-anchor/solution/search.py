#!/usr/bin/env python3
"""granite-anchor search driver.

Reads a state-space config (start, goal, nodes with board rows, directed
edges), runs a deterministic BFS over the reachable component, and emits five
kinds of artifact into OUTDIR:

  frontier_<d>.txt   one line per node-id at depth d (ascending)
  frontier.sha256    "<sha256>  frontier_<d>.txt" per depth
  depth_summary.txt  CSV header "depth,count" then one row per depth
  dag_edges.csv      CSV header "from,to" then the BFS-search-tree edges
                     oriented parent->child, sorted
  move_trace.json    {"boards": [[row-str,...], ...]} for the shortest path
                     from start to goal (start's rows first, goal's rows last)

Edges to node ids absent from "nodes" are ignored (orphan edges); duplicate
and self-loop edges collapse because each node is claimed exactly once at its
shallowest depth.
"""
import sys, json, hashlib, os
from collections import deque


def run_search(cfg):
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
    return start, goal, nodes, dist, parent, maxd


def write_artifacts(outdir, start, goal, nodes, dist, parent, maxd):
    os.makedirs(outdir, exist_ok=True)

    sha_lines = []
    for d in range(0, maxd + 1):
        members = sorted(n for n in dist if dist[n] == d)
        fname = "frontier_%d.txt" % d
        content = "\n".join(map(str, members)) + ("\n" if members else "")
        with open(os.path.join(outdir, fname), "w") as f:
            f.write(content)
        sha_lines.append("%s  %s" % (hashlib.sha256(content.encode()).hexdigest(), fname))
    with open(os.path.join(outdir, "frontier.sha256"), "w") as f:
        f.write("\n".join(sha_lines) + ("\n" if sha_lines else ""))

    with open(os.path.join(outdir, "depth_summary.txt"), "w") as f:
        f.write("depth,count\n")
        for d in range(0, maxd + 1):
            f.write("%d,%d\n" % (d, sum(1 for n in dist if dist[n] == d)))

    dag = sorted((parent[v], v) for v in parent)
    with open(os.path.join(outdir, "dag_edges.csv"), "w") as f:
        f.write("from,to\n")
        for a, b in dag:
            f.write("%d,%d\n" % (a, b))

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
    with open(os.path.join(outdir, "move_trace.json"), "w") as f:
        json.dump({"boards": boards}, f)


def main():
    cfg_path = sys.argv[1] if len(sys.argv) > 1 else "/app/config.json"
    outdir = sys.argv[2] if len(sys.argv) > 2 else "/app"
    with open(cfg_path) as f:
        cfg = json.load(f)
    start, goal, nodes, dist, parent, maxd = run_search(cfg)
    write_artifacts(outdir, start, goal, nodes, dist, parent, maxd)


if __name__ == "__main__":
    main()
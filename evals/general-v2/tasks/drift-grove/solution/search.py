#!/usr/bin/env python3
"""Grove tile-solver: BFS by depth over a 3x3 sliding-tile board.

usage: search.py <puzzle.json> [out.json]

puzzle.json: {"board": [9 ints], "goal": [9 ints]}  (0 == empty cell)

Writes a JSON report:
  layers      : one list of states per BFS depth (states at distance d),
                disjoint across depths, union == every reachable state
  chain       : shortest board-state walk from board to goal
  card, depth : number of reachable states and goal distance
  solved      : whether the goal is reachable
"""
import json
import sys
from collections import deque


def neighbors(state):
    """One tile slides into the empty cell at a time."""
    empty = state.index(0)
    adj = []
    r, c = divmod(empty, 3)
    for dr, dc in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        nr, nc = r + dr, c + dc
        if 0 <= nr < 3 and 0 <= nc < 3:
            other = nr * 3 + nc
            cell = [list(state)]
            cell[0][empty], cell[0][other] = cell[0][other], cell[0][empty]
            adj.append(tuple(cell[0]))
    return adj


def bfs_depth(start, goal):
    """Layer-by-layer BFS. Returns layers list, parent map, depth map."""
    layers = [[start]]
    dist = {start: 0}
    parent = {start: None}
    frontier = [start]
    while True:
        nxt = []
        for st in frontier:
            for nb in neighbors(st):
                if nb not in dist:
                    dist[nb] = dist[st] + 1
                    parent[nb] = st
                    nxt.append(nb)
        if not nxt:
            break
        layers.append(nxt)
        frontier = nxt
    return layers, parent, dist


def main() -> int:
    inp = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else "/app/tile-solution.json"
    with open(inp) as fh:
        spec = json.load(fh)
    start = tuple(spec["board"])
    goal = tuple(spec["goal"])
    layers, parent, dist = bfs_depth(start, goal)
    chain = []
    if goal in dist:
        node = goal
        while node is not None:
            chain.append(node)
            node = parent[node]
        chain.reverse()
    report = {
        "start": list(start),
        "goal": list(goal),
        "solved": goal in dist,
        "card": len(dist),
        "depth": dist.get(goal, -1) if goal in dist else len(layers) - 1,
        "layers": [[list(s) for s in layer] for layer in layers],
        "chain": [list(s) for s in chain],
        "frontier_disjoint": True,
    }
    with open(out, "w") as fh:
        json.dump(report, fh)
    return 0


if __name__ == "__main__":
    sys.exit(main())
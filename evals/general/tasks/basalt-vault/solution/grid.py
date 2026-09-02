#!/usr/bin/env python3
"""Basalt Vault maze explorer (HTTP/JSON client).

Usage:
    python3 /app/grid.py <maze-id> [--port P] [--out /app/map.txt]

Connects to the Basalt Vault maze service, opens a session for <maze-id>,
explores the unknown grid cell-by-cell with /examine + /move (recording every
wall and collecting the treasure), finishes exactly on the exit, registers the
session, and writes the fully-explored map plus the winning move list to --out.

Exits 0 on success.
"""
import argparse
import json
import sys
import urllib.request
from collections import deque


def post(base, path, payload):
    req = urllib.request.Request(
        base + "/" + path,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read().decode())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("maze_id")
    ap.add_argument("--port", type=int, default=8123)
    ap.add_argument("--out", default="/app/map.txt")
    args = ap.parse_args()

    base = "http://127.0.0.1:%d" % args.port
    mid = args.maze_id
    moves = []  # list of (sr, sc, dr, dc)

    st = post(base, "start", {"id": mid})
    if not st.get("ok"):
        sys.stderr.write(json.dumps(st) + "\n")
        return 1
    rows, cols = st["rows"], st["cols"]
    pos = list(st["pos"])
    start = tuple(pos)

    grid = {}            # (r,c) -> char as known ('.','#','S','T','E')
    grid[start] = "S"
    visited = {start}
    stack = [start]

    dirs = [(-1, 0), (1, 0), (0, -1), (0, 1)]

    def go(r, c):
        nonlocal pos
        if [r, c] == pos:
            return
        out = post(base, "move", {"id": mid, "r": r, "c": c})
        if not out.get("ok"):
            sys.stderr.write("move failed: %s\n" % json.dumps(out))
            raise SystemExit(1)
        moves.append((pos[0], pos[1], r, c))
        pos[:] = [r, c]
        grid[(r, c)] = out.get("cell", ".")

    # ---- full depth-first exploration of the passable component ----
    while stack:
        r, c = stack[-1]
        if pos != [r, c]:
            go(r, c)
        ex = post(base, "examine", {"id": mid})
        for name, dr, dc in (("up", -1, 0), ("down", 1, 0),
                             ("left", 0, -1), ("right", 0, 1)):
            nr, nc = r + dr, c + dc
            if 0 <= nr < rows and 0 <= nc < cols:
                grid[(nr, nc)] = ex[name]
        # pick first unvisited passable neighbour
        nxt = None
        for dr, dc in dirs:
            nr, nc = r + dr, c + dc
            if 0 <= nr < rows and 0 <= nc < cols and (nr, nc) not in visited:
                if grid.get((nr, nc), "#") != "#":
                    nxt = (nr, nc)
                    break
        if nxt is None:
            if len(stack) > 1:
                parent = stack[-2]
                stack.pop()
                go(*parent)
            else:
                stack.pop()
        else:
            stack.append(nxt)
            visited.add(nxt)
            go(*nxt)

    # ---- locate treasure and exit from what we revealed ----
    treasure_pos = exit_pos = None
    for (r, c), ch in grid.items():
        if ch == "T":
            treasure_pos = (r, c)
        elif ch == "E":
            exit_pos = (r, c)

    if treasure_pos is None or exit_pos is None:
        sys.stderr.write("failed to locate treasure/exit\n")
        return 1

    # ensure the treasure was physically collected (move onto it if not)
    if not post(base, "state", {"id": mid}).get("collected"):
        r, c = treasure_pos
        for dr, dc in dirs:
            nr, nc = r + dr, c + dc
            if 0 <= nr < rows and 0 <= nc < cols and grid.get((nr, nc)) != "#":
                go(nr, nc)   # step off
                go(r, c)     # step back onto treasure -> collects
                break

    # ---- walk to the exit over passable cells (BFS shortest path) ----
    def passable(r, c):
        return 0 <= r < rows and 0 <= c < cols and grid.get((r, c), "#") != "#"

    prev = {}
    bfsq = deque([tuple(pos)])
    prev[tuple(pos)] = None
    while bfsq:
        cur = bfsq.popleft()
        if cur == exit_pos:
            break
        for dr, dc in dirs:
            nxt = (cur[0] + dr, cur[1] + dc)
            if passable(*nxt) and nxt not in prev:
                prev[nxt] = cur
                bfsq.append(nxt)
    path = []
    cur = exit_pos
    while cur is not None:
        path.append(cur)
        cur = prev.get(cur)
    path.reverse()
    for i in range(1, len(path)):
        go(*path[i])

    # ---- finish exactly at the exit, then register the session ----
    fin = post(base, "finish", {"id": mid})
    if not fin.get("ok"):
        sys.stderr.write("finish failed: %s\n" % json.dumps(fin))
        return 1
    post(base, "register", {"id": mid})

    # ---- write the map: full grid + winning move list ----
    special = {treasure_pos: "T", exit_pos: "E", start: "S"}
    lines = ["BASALT-VAULT-MAP", "maze=%s" % mid, "rows=%d" % rows,
             "cols=%d" % cols]
    for r in range(rows):
        row = []
        for c in range(cols):
            if (r, c) in special:
                row.append(special[(r, c)])
            elif (r, c) in visited:
                row.append(".")
            else:
                row.append("#")
        lines.append(" ".join(row))
    lines.append("MOVES")
    for sr, sc, dr, dc in moves:
        lines.append("%d,%d->%d,%d" % (sr, sc, dr, dc))
    lines.append("END")
    with open(args.out, "w") as fh:
        fh.write("\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())

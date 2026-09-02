#!/usr/bin/env python3
"""Dune Beacon maze server.

An interactive, turn-based maze.  The maze layout is loaded from the file named
by argv[1] (a grid of '#', ' ', 'S' and 'E').  Commands are read from stdin one
JSON object per line:

    {"moves": ["n","s","e","w", ...]}

Each element of `moves` is a single step. Steps are applied sequentially in the
order given. For every step the server answers with exactly one token, in the
same order, via a single JSON response line of the form:

    {"responses": ["moved", "wall", "exit", ...]}

Token semantics:
    "moved"  -> the step succeeded; you are now in the new cell.
    "wall"   -> the step was blocked by a wall; you stay where you were.
    "exit"   -> the step succeeded and you moved into the maze exit cell.

The client must keep track of its own position from these responses; the server
does not reveal grid contents beyond what a step tells you.

The reply stream always goes to stdout and is flushed after every line so the
full response can be parsed without closing the connection.

To stop the server gracefully, send {"bye": true}; the server stops reading.
"""
import json
import sys

DIRS = {"n": (-1, 0), "s": (1, 0), "e": (0, 1), "w": (0, -1)}


def load(filename):
    rows = []
    with open(filename, "r") as fh:
        for raw in fh:
            line = raw.rstrip("\n").rstrip("\r")
            if line == "":
                continue
            rows.append(line)
    grid = [list(r) for r in rows]
    h = len(grid)
    w = len(grid[0]) if h else 0
    start = exitp = None
    for r in range(h):
        for c in range(w):
            if grid[r][c] == "S":
                start = (r, c)
            elif grid[r][c] == "E":
                exitp = (r, c)
    if start is None or exitp is None:
        raise ValueError("maze must contain S and E")
    return grid, h, w, start, exitp


def main():
    grid, h, w, start, exitp = load(sys.argv[1])
    pos = list(start)
    sys.stdout.write(
        "READY ROWS=%d COLS=%d START=%d,%d\n" % (h, w, pos[0], pos[1]))
    sys.stdout.flush()
    try:
        for raw in sys.stdin:
            line = raw.strip()
            if not line:
                continue
            try:
                req = json.loads(line)
            except ValueError:
                sys.stdout.write('{"error":"bad_json"}\n')
                sys.stdout.flush()
                continue
            if req.get("bye"):
                sys.stdout.write('{"responses":[]}\n')
                sys.stdout.flush()
                break
            moves = req.get("moves", [])
            if not isinstance(moves, list):
                sys.stdout.write('{"error":"moves_not_list"}\n')
                sys.stdout.flush()
                continue
            resps = []
            for m in moves:
                if m not in DIRS:
                    resps.append("wall")
                    continue
                dr, dc = DIRS[m]
                nr, nc = pos[0] + dr, pos[1] + dc
                if not (0 <= nr < h and 0 <= nc < w) or grid[nr][nc] == "#":
                    resps.append("wall")
                    continue
                pos = [nr, nc]
                if (nr, nc) == exitp:
                    resps.append("exit")
                else:
                    resps.append("moved")
            sys.stdout.write(json.dumps({"responses": resps}) + "\n")
            sys.stdout.flush()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
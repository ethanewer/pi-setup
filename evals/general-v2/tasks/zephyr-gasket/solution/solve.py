#!/usr/bin/env python3
"""Solve zephyr-gasket.  Modes:
   solve.py                    -> write /app/answer.json (visible fixtures)
   solve.py maze <id> <out>    -> explore unknown maze, write JSON
   solve.py game <pos.json> <out> -> winning (mating) moves for a position
   solve.py selfcheck          -> validate on the reference maze fixture
"""
import json
import os
import sys
from collections import deque

_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _DIR)
import mazeapi  # noqa: E402

DIRS = ('N', 'S', 'E', 'W')
DELTA = {'N': (-1, 0), 'S': (1, 0), 'E': (0, 1), 'W': (0, -1)}

VISIBLE_MAZES = ["maze-verdigris", "maze-brass"]
VISIBLE_GAMES = ["kinghand-1", "kinghand-2"]


def _dir_between(a, b):
    ar, ac = a
    br, bc = b
    if br == ar - 1:
        return 'N'
    if br == ar + 1:
        return 'S'
    if bc == ac - 1:
        return 'W'
    return 'E'


def _neighbors(rows, cols, open_map, cell):
    r, c = cell
    out = []
    for d in DIRS:
        opens = open_map[cell] if isinstance(open_map.get(cell), set) else open_map.get(cell, ())
        if d not in opens:
            continue
        dr, dc = DELTA[d]
        nr, nc = r + dr, c + dc
        if 0 <= nr < rows and 0 <= nc < cols:
            out.append((nr, nc))
    return out


def _bfs_path(rows, cols, open_map, start, goal):
    prev = {start: None}
    q = deque([start])
    while q:
        cur = q.popleft()
        if cur == goal:
            break
        for nb in _neighbors(rows, cols, open_map, cur):
            if nb not in prev:
                prev[nb] = cur
                q.append(nb)
    if goal not in prev:
        return []
    seg = []
    node = goal
    while node != start:
        p = prev[node]
        seg.append(_dir_between(p, node))
        node = p
    return seg[::-1]


def explore_maze(m):
    rows, cols = m.dimensions()
    start = tuple(m.start)
    open_map = {start: set()}
    exit_cell = None
    pos = start
    path = [pos]

    def record():
        open_map[pos] = {d for d in DIRS if m.peek(d)}

    record()
    if m.at_exit():
        exit_cell = pos

    while True:
        if m.at_exit():
            exit_cell = pos
        opened = [d for d in DIRS if m.peek(d)]
        moved = False
        for d in opened:
            dr, dc = DELTA[d]
            nb = (pos[0] + dr, pos[1] + dc)
            if 0 <= nb[0] < rows and 0 <= nb[1] < cols and nb not in open_map:
                if not m.move(d):
                    raise RuntimeError("move failed %s->%s" % (pos, d))
                pos = nb
                path.append(pos)
                record()
                if m.at_exit():
                    exit_cell = pos
                moved = True
                break
        if moved:
            continue
        if len(path) <= 1:
            break
        path.pop()
        prev = path[-1]
        if not m.move(_dir_between(pos, prev)):
            raise RuntimeError("backtrack failed %s->%s" % (pos, prev))
        pos = prev

    # map for every cell
    map_obj = {}
    for r in range(rows):
        for c in range(cols):
            opens = open_map.get((r, c), set())
            map_obj["%d,%d" % (r, c)] = [1 if d in opens else 0 for d in DIRS]

    if exit_cell is None:
        raise RuntimeError("exit never determined for maze %s" % m.maze_id)

    return {
        "rows": rows,
        "cols": cols,
        "map": map_obj,
        "exit": "%d,%d" % exit_cell,
        "path": _bfs_path(rows, cols, open_map, start, exit_cell),
        "budget_remaining": m.budget(),
    }


def solve_maze(maze_id):
    return explore_maze(mazeapi.Maze(maze_id))


# ---------------- chess ----------------
KH = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]
KN = [(-2, -1), (-2, 1), (-1, -2), (-1, 2), (1, -2), (1, 2), (2, -1), (2, 1)]
ORTH = [(1, 0), (-1, 0), (0, 1), (0, -1)]
DIAG = [(1, 1), (1, -1), (-1, 1), (-1, -1)]
FILES = 'abcdefgh'


def _rc(sq):
    return (int(sq[1]) - 1, FILES.index(sq[0]))


def _sc(r, c):
    return FILES[c] + str(r + 1)


def _inb(r, c):
    return 0 <= r < 8 and 0 <= c < 8


def _placed(pieces):
    b = [[None] * 8 for _ in range(8)]
    for col, typ, sq in pieces:
        r, c = _rc(sq)
        b[r][c] = (col, typ)
    return b


def _attacked(b, color):
    out = set()
    for r in range(8):
        for c in range(8):
            p = b[r][c]
            if not p or p[0] != color:
                continue
            typ = p[1]
            if typ == 'k':
                for dr, dc in KH:
                    if _inb(r + dr, c + dc):
                        out.add((r + dr, c + dc))
            elif typ == 'n':
                for dr, dc in KN:
                    if _inb(r + dr, c + dc):
                        out.add((r + dr, c + dc))
            else:
                dirs = []
                if typ in ('q', 'r'):
                    dirs += ORTH
                if typ in ('q', 'b'):
                    dirs += DIAG
                for dr, dc in dirs:
                    rr, cc = r + dr, c + dc
                    while _inb(rr, cc):
                        out.add((rr, cc))
                        if b[rr][cc] is not None:
                            break
                        rr += dr
                        cc += dc
    return out


def _king(b, color):
    for r in range(8):
        for c in range(8):
            if b[r][c] == (color, 'k'):
                return (r, c)
    return None


def _in_check(b, color):
    k = _king(b, color)
    if k is None:
        return False
    return k in _attacked(b, 'b' if color == 'w' else 'w')


def _apply(b, src, dst):
    nb = [row[:] for row in b]
    nb[dst[0]][dst[1]] = nb[src[0]][src[1]]
    nb[src[0]][src[1]] = None
    return nb


def _ps_moves(b, r, c):
    col, typ = b[r][c]
    out = []
    if typ == 'k':
        for dr, dc in KH:
            if _inb(r + dr, c + dc):
                t = b[r + dr][c + dc]
                if t is None or t[0] != col:
                    out.append((r + dr, c + dc))
    elif typ == 'n':
        for dr, dc in KN:
            if _inb(r + dr, c + dc):
                t = b[r + dr][c + dc]
                if t is None or t[0] != col:
                    out.append((r + dr, c + dc))
    else:
        dirs = []
        if typ in ('q', 'r'):
            dirs += ORTH
        if typ in ('q', 'b'):
            dirs += DIAG
        for dr, dc in dirs:
            rr, cc = r + dr, c + dc
            while _inb(rr, cc):
                t = b[rr][cc]
                if t is None:
                    out.append((rr, cc))
                else:
                    if t[0] != col:
                        out.append((rr, cc))
                    break
                rr += dr
                cc += dc
    return out


def _legal(b, color):
    res = []
    for r in range(8):
        for c in range(8):
            bset = b[r][c]
            if bset and bset[0] == color:
                for (nr, nc) in _ps_moves(b, r, c):
                    nb = _apply(b, (r, c), (nr, nc))
                    if not _in_check(nb, color):
                        res.append(((r, c), (nr, nc)))
    return res


def _mate(b, color):
    if not _in_check(b, color):
        return False
    return len(_legal(b, color)) == 0


def winning_moves(position):
    pieces = position['pieces']
    side = position.get('side_to_move', 'w')
    opp = 'b' if side == 'w' else 'w'
    b = _placed(pieces)
    res = set()
    for (r, c), (nr, nc) in _legal(b, side):
        nb = _apply(b, (r, c), (nr, nc))
        if _mate(nb, opp):
            res.add(_sc(r, c) + _sc(nr, nc))
    return sorted(res)


def selfcheck():
    import reference_maze
    rows, cols = reference_maze.DIMS
    start = reference_maze.START
    seen = set()
    stack = [start]
    while stack:
        cur = stack.pop()
        if cur in seen:
            continue
        seen.add(cur)
        for nb in _neighbors(rows, cols, reference_maze.OPEN, cur):
            if nb not in seen:
                stack.append(nb)
    coverage = len(seen)
    total = rows * cols
    print("SELFCHECK-COVERAGE=%d/%d" % (coverage, total))
    return coverage == total


def make_answer():
    ans = {"mazes": {}, "games": {}}
    for mid in VISIBLE_MAZES:
        ans["mazes"][mid] = solve_maze(mid)
    for gid in VISIBLE_GAMES:
        p = json.load(open(os.path.join(_DIR, "games", gid + ".json")))
        ans["games"][gid] = winning_moves(p)
    return ans


def main():
    argv = sys.argv[1:]
    if not argv:
        out = os.path.join(_DIR, "answer.json")
        with open(out, "w") as f:
            json.dump(make_answer(), f, indent=2)
        print("wrote " + out)
    elif argv[0] == "maze":
        out = argv[2] if len(argv) > 2 else "/tmp/maze_out.json"
        with open(out, "w") as f:
            json.dump(solve_maze(argv[1]), f, indent=2)
        print("wrote " + out)
    elif argv[0] == "game":
        out = argv[2] if len(argv) > 2 else "/tmp/game_out.json"
        with open(out, "w") as f:
            json.dump(winning_moves(json.load(open(argv[1]))), f, indent=2)
        print("wrote " + out)
    elif argv[0] == "selfcheck":
        ok = selfcheck()
        print("SELFCHECK-OK=%d" % (1 if ok else 0))
        sys.exit(0 if ok else 1)
    else:
        print("usage")
        sys.exit(2)


if __name__ == "__main__":
    main()
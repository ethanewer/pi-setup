#!/usr/bin/env python3
"""iris-anchor block path planner.

Finds a valid sequence of actions moving a robot from {start} to {goal} on an
elevation grid, where tall cliffs can be bridged by stacking carried blocks.
Generalizes to arbitrary grid JSON.

Usage:  python3 planner.py <grid.json> -o <out.json>
"""
import json, sys


def neighbors(r, c, R, C):
    for dr, dc in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        nr, nc = r + dr, c + dc
        if 0 <= nr < R and 0 <= nc < C:
            yield nr, nc


def addcnt(add, t):
    for (ar, ac), cnt in add:
        if (ar, ac) == t:
            return cnt
    return 0


def compress(add):
    d = {}
    for (ar, ac), cnt in add:
        d[(ar, ac)] = d.get((ar, ac), 0) + cnt
    return tuple(sorted(k for k in d.items() if k[1] > 0))


def solve(grid):
    R = grid['rows']; C = grid['cols']
    base = grid['base']
    blk = grid['blocked']
    if blk and isinstance(blk[0], list):
        blocked = {tuple(b) for b in blk}
    else:
        blocked = {(r, c) for r in range(R) for c in range(C) if blk[r][c]}
    start = tuple(grid['start']); goal = tuple(grid['goal'])
    cap = grid.get('capacity', 3)
    max_stack = grid.get('max_stack', 2)
    start_carry = grid.get('start_carry', cap)
    if start in blocked or goal in blocked:
        return None

    def elev(pos, add):
        return base[pos[0]][pos[1]] + addcnt(add, pos)

    init = (start[0], start[1], start_carry, ())
    seen = {init}
    q = [(init, [])]
    qi = 0
    while qi < len(q):
        (r, c, carry, add), path = q[qi]; qi += 1
        if (r, c) == goal:
            return path
        my_e = elev((r, c), add)
        for nr, nc in neighbors(r, c, R, C):
            if (nr, nc) in blocked:
                continue
            if elev((nr, nc), add) <= my_e + 1:
                ns = (nr, nc, carry, add)
                if ns not in seen:
                    seen.add(ns)
                    q.append((ns, path + [{'type': 'move', 'to': [nr, nc]}]))
        targets = [(r, c)] + list(neighbors(r, c, R, C))
        for t in targets:
            if t in blocked:
                continue
            if carry > 0 and addcnt(add, t) < max_stack:
                new_add = compress(add + ((t, addcnt(add, t) + 1),))
                ns = (r, c, carry - 1, new_add)
                if ns not in seen:
                    seen.add(ns)
                    q.append((ns, path + [{'type': 'place', 'at': [t[0], t[1]]}]))
        for t in targets:
            if t in blocked:
                continue
            cnt = addcnt(add, t)
            if cnt > 0 and carry < cap:
                rest = tuple(x for x in add if not (x[0] == t))
                new_add = rest if cnt - 1 == 0 else compress(rest + ((t, cnt - 1),))
                ns = (r, c, carry + 1, new_add)
                if ns not in seen:
                    seen.add(ns)
                    q.append((ns, path + [{'type': 'pick', 'at': [t[0], t[1]]}]))
    return None


if __name__ == '__main__':
    import sys
    out = 'out.json'
    for i, a in enumerate(sys.argv):
        if a == '-o':
            out = sys.argv[i + 1]
    grid = json.load(open(sys.argv[1]))
    path = solve(grid)
    if path is None:
        json.dump({'actions': [], 'reaches': False}, open(out, 'w'))
        print('no path found', file=sys.stderr)
        sys.exit(2)
    json.dump({'actions': path, 'reaches': True}, open(out, 'w'))
    print(f'wrote {len(path)} actions to {out}')
"""Independent reference engine used by the zephyr-gasket verifier.

Implements (a) the standard chess-mate subset used by the task and (b) maze
ground-truth validation. This is a SEPARATE implementation from the candidate's
/app/solve.py; the verifier uses it to re-derive expected results from raw
fixtures and hidden inputs so it never trusts the candidate's own logic.
"""
import sys

FILES = 'abcdefgh'


def _rc(sq):
    return (int(sq[1]) - 1, FILES.index(sq[0]))


def _sc(r, c):
    return FILES[c] + str(r + 1)


def _inb(r, c):
    return 0 <= r < 8 and 0 <= c < 8


KH = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]
KN = [(-2, -1), (-2, 1), (-1, -2), (-1, 2), (1, -2), (1, 2), (2, -1), (2, 1)]
ORTH = [(1, 0), (-1, 0), (0, 1), (0, -1)]
DIAG = [(1, 1), (1, -1), (-1, 1), (-1, -1)]


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


def expected_mates(position):
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


def check_game(reported, position):
    return reported == expected_mates(position)


# ---- maze validation -------------------------------------------------------
DELTA = {'N': (-1, 0), 'S': (1, 0), 'E': (0, 1), 'W': (0, -1)}
DIRS = ('N', 'S', 'E', 'W')


def check_maze(reported, maze_id, mazeapi):
    """Return (ok, reason). against ground truth derived from mazeapi."""
    mm = mazeapi.Maze(maze_id)
    rows, cols = mm.dimensions()
    if reported.get('rows') != rows or reported.get('cols') != cols:
        return False, 'dimension mismatch'
    gt = mm._ground_open  # dict cell -> {d: open_bool}
    m = reported.get('map')
    if not isinstance(m, dict):
        return False, 'map missing'
    for r in range(rows):
        for c in range(cols):
            key = '%d,%d' % (r, c)
            val = m.get(key)
            if val is None or not isinstance(val, list) or len(val) != 4:
                return False, 'map cell missing %s' % key
            exp = [1 if gt[(r, c)][d] else 0 for d in DIRS]
            if val != exp:
                return False, 'wall mismatch at %s' % key
    # exit
    if reported.get('exit') != '%d,%d' % tuple(mm.exit):
        return False, 'exit mismatch'
    # path legality
    path = reported.get('path')
    if not isinstance(path, list):
        return False, 'path missing'
    rn, cn = mm.start
    for step in path:
        if step not in DELTA:
            return False, 'bad step %r' % step
        dr, dc = DELTA[step]
        if not gt[(rn, cn)][step]:
            return False, 'step crosses a wall'
        rn += dr
        cn += dc
    if (rn, cn) != tuple(mm.exit):
        return False, 'path does not reach exit'
    if reported.get('budget_remaining', 0) < 0:
        return False, 'exceeded move budget'
    return True, 'ok'
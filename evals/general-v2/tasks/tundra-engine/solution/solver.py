#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
tundra-engine — a game & maze search bench solver (reference implementation).

Reads a JSON "spec" file of independent cases and writes a JSON "answer" file.
CLI:  python3 /app/solve.py [INPUT.json [OUTPUT.json]]
defaults: INPUT=/app/spec.json  OUTPUT=/app/answer.json

Spec format:
    {"cases": [ <case>, ... ]}          (case objects may be any of the types
                                         below and must carry a unique "id")
Answer format:
    {"answers": { "<id>": <result>, ... }}

Case types (input & output contracts). Every case result echoes its "id" and
"type".

1) "tiles"  — optimal sliding-tile (sliding block puzzle) solver
   input:  {"id","type":"tiles","grid":[[int,...]],"goal"?:[[int,...]]}
           grid is a rows x cols rectangular array holding every value
           0..(rows*cols-1) exactly once; 0 is the blank. goal defaults to the
           solved arrangement (rows-major 1..C-1,0 per row; 0 bottom-right).
   output: {"id","type","rows","cols","solvable","solved","min_moves",
            "canonical_initial","canonical_goal","states","path","move_count"}
           - solvable: parity of the arrangement w.r.t. the target (bool)
           - solved:   solvable and a solution was found (bool)
           - min_moves: minimal number of moves to reach goal (int, -1 if
             unsolvable or no solution found)
           - canonical_initial / canonical_goal: the fixed-length zero-padded
             row-major string (each cell exactly 2 digits, concatenated) of the
             initial and goal boards (length = 2*rows*cols)
           - states: list of canonical strings, one per move AFTER that move
             (length == min_moves; empty when min_moves==0)
           - path:    tab-separated optimal path; one line per move, format
             "srcRow,srcCol\tdstRow,dstCol\ttileValue" — the tile in the source
             cell slides into the blank destination cell
           - move_count: number of lines in path (== min_moves)
           A run with a single move/lone swap is handled; 0 = already solved.

2) "snapshot" — canonical zero-padded serialization of a grid
   input:  {"id","type":"snapshot","grid":[[int,...],...]}
   output: {"id","type","valid","canonical"}
           - valid: true iff grid is a non-empty rectangular list of lists of
             ints in 0..99
           - canonical: the fixed-length string (each cell exactly 2 digits,
             row-major), or "" when valid is false

3) "mahjong" — detect the seven-pairs and thirteen-orphans winning patterns
   input:  {"id","type":"mahjong","hand":["A1",...]}
           tiles are codes: suits A,B,C with ranks 1..9 ("A1".."A9",
           "B1".."B9","C1".."C9") plus seven honor tiles "H1".."H7".
           A hand is 14 tiles. Terminal/honor group (TH) =
           {A1,A9,B1,B9,C1,C9,H1..H7}.
   output: {"id","type","valid","win","pattern"}
           - valid: hand has exactly 14 tiles and every code is in the
             vocabulary
           - win:   true iff valid and one of the two special patterns holds
           - pattern: "seven_pairs" | "thirteen_orphans" | "none"
             seven_pairs: the 14 tiles form exactly 7 pairs, i.e. the multiset
             of counts is seven values each equal to 2 (no tile appears 4x).
             thirteen_orphans: the hand contains each of the 13 TH tiles at
             least once, nothing outside TH, so with 14 tiles exactly one TH
             tile appears twice and the other 12 once.  pattern=="none" for a
             valid non-winning hand and for any invalid hand.

4) "connect" — block an opponent four-in-a-row threat
   input:  {"id","type":"connect","board":["...","O..",...]}
           board rows are equal-length strings over {'O' (opponent),
           'X' (ours), '.' (empty)}.
   output: {"id","type","block","threats"}
           - threats: count of distinct threat-end cells found
           - block:   [r,c] of a threat-end cell, or null when there is no
             immediate four-in-a-row threat.
           A threat-end cell is an EMPTY cell that is the open end adjacent to
           a contiguous line of exactly 3 opponent stones (horizontal,
           vertical or either diagonal). When several valid block cells exist,
           any of them is acceptable (row-major smallest is returned here).

5) "maze" — shortest-turn navigation within a move budget
   input:  {"id","type":"maze","grid":["...","S..G",...],"max_turns":int}
           grid rows are equal-length strings over '#','.','S','G' ('#'
           wall/passable-only '.' cells; exactly one 'S' and one 'G'). One
           move = step to a 4-neighbour; diagonal moves are not allowed.
   output: {"id","type","reachable","min_turns","within_budget","moves"}
           - reachable: False if S or G is missing/unreachable (then min_turns
             = -1, within_budget False, moves "")
           - min_turns: minimal number of moves S->G (0 if S==G)
           - within_budget: min_turns <= max_turns (False when unreachable)
           - moves:      "URDL"-string of a minimal path (empty if unreachable
             or min_turns==0); any minimal path is acceptable.

The solver must be *general*: given any such spec (including empty "cases",
absent optional fields, and the edge cases documented in the task statement) it
produces the documented output and exits 0. It never reads /tests or /solution.
"""

import heapq
import json
import os
import sys

# ---------------------------------------------------------------------------
# shared helpers
# ---------------------------------------------------------------------------

TILE_VOCAB = set()
for suit in ("A", "B", "C"):
    for rank in range(1, 10):
        TILE_VOCAB.add("%s%d" % (suit, rank))
TILE_VOCAB.update("H%d" % i for i in range(1, 8))

TH13 = {"A1", "A9", "B1", "B9", "C1", "C9",
        "H1", "H2", "H3", "H4", "H5", "H6", "H7"}


def canonical(grid):
    """Fixed-length zero-padded row-major string of a rectangular int grid."""
    if not grid:
        return ""
    out = []
    for row in grid:
        for v in row:
            out.append("%02d" % v)
    return "".join(out)


def parse_grid_or_none(g):
    if not isinstance(g, list) or not g:
        return None
    ncols = None
    for row in g:
        if not isinstance(row, list):
            return None
        if ncols is None:
            ncols = len(row)
        elif len(row) != ncols:
            return None
        if ncols == 0:
            return None
    return g


def default_goal(rows, cols):
    vals = list(range(1, rows * cols)) + [0]
    return [vals[r * cols:(r + 1) * cols] for r in range(rows)]


# ---------------------------------------------------------------------------
# tiles (optimal sliding puzzle)  — A* with Manhattan (admissible -> optimal)
# ---------------------------------------------------------------------------

def _inversions(flat):
    seq = [t for t in flat if t != 0]
    inv = 0
    for i in range(len(seq)):
        for j in range(i + 1, len(seq)):
            if seq[i] > seq[j]:
                inv += 1
    return inv


def _tile_solvable(flat, rows, cols):
    inv = _inversions(flat)
    blank_row = flat.index(0) // cols
    blank_from_bottom = (rows - 1) - blank_row
    if cols % 2 == 1:
        return inv % 2 == 0
    return (inv + blank_from_bottom) % 2 == 0


def solve_tiles(grid, goal):
    rows, cols = len(grid), len(grid[0])
    start = tuple(v for r in grid for v in r)
    if goal is None:
        goal = default_goal(rows, cols)
    goal_flat = tuple(v for r in goal for v in r)

    canon_init = canonical(grid)
    canon_goal = canonical(goal)

    if not _tile_solvable(start, rows, cols):
        return {
            "rows": rows, "cols": cols, "solvable": False, "solved": False,
            "min_moves": -1, "canonical_initial": canon_init,
            "canonical_goal": canon_goal, "states": [], "path": "", "move_count": 0,
        }

    if start == goal_flat:
        return {
            "rows": rows, "cols": cols, "solvable": True, "solved": True,
            "min_moves": 0, "canonical_initial": canon_init,
            "canonical_goal": canon_goal, "states": [], "path": "", "move_count": 0,
        }

    # goal position lookup for Manhattan
    gpos = {}
    for idx, v in enumerate(goal_flat):
        gpos[v] = (idx // cols, idx % cols)

    def manhattan(tup):
        d = 0
        for idx, v in enumerate(tup):
            if v == 0:
                continue
            r, c = divmod(idx, cols)
            gr, gc = gpos[v]
            d += abs(r - gr) + abs(c - gc)
        return d

    start_h = manhattan(start)
    heap = [(start_h, 0, start, ())]
    seen = {}
    best = None
    count = 0
    while heap:
        f, g, tup, moves = heapq.heappop(heap)
        if seen.get(tup, 1 << 30) <= g:
            continue
        seen[tup] = g
        if tup == goal_flat:
            best = moves
            break
        # expand: blank slides
        blank_idx = tup.index(0)
        br, bc = divmod(blank_idx, cols)
        moves_list = list(moves)
        for dr, dc in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            nr, nc = br + dr, bc + dc
            if 0 <= nr < rows and 0 <= nc < cols:
                nidx = nr * cols + nc
                nxt = list(tup)
                tile = nxt[nidx]
                nxt[blank_idx], nxt[nidx] = nxt[nidx], nxt[blank_idx]
                nxt = tuple(nxt)
                ng = g + 1
                nh = manhattan(nxt)
                heapq.heappush(heap, (ng + nh, count, nxt,
                                      moves_list + [(br, bc, nidx, tile)]))
                count += 1
    else:
        best = None

    if best is None:
        return {
            "rows": rows, "cols": cols, "solvable": True, "solved": False,
            "min_moves": -1, "canonical_initial": canon_init,
            "canonical_goal": canon_goal, "states": [], "path": "", "move_count": 0,
        }

    # build states + path
    board = [list(r) for r in grid]
    states = []
    path_lines = []
    for (br, bc, nidx, tile) in best:
        r, c = divmod(nidx, cols)
        # blank is at (br,bc); tile slides from (r,c) into (br,bc)
        board[r][c], board[br][bc] = board[br][bc], board[r][c]
        states.append(canonical(board))
        path_lines.append("%d,%d\t%d,%d\t%d" % (r, c, br, bc, tile))

    return {
        "rows": rows, "cols": cols, "solvable": True, "solved": True,
        "min_moves": len(best), "canonical_initial": canon_init,
        "canonical_goal": canon_goal, "states": states,
        "path": "\n".join(path_lines), "move_count": len(best),
    }


# ---------------------------------------------------------------------------
# snapshot (canonical zero-padded string)
# ---------------------------------------------------------------------------

def solve_snapshot(grid):
    g = parse_grid_or_none(grid)
    if g is None:
        return {"valid": False, "canonical": ""}
    for row in g:
        for v in row:
            if not isinstance(v, int) or isinstance(v, bool) or not (0 <= v <= 99):
                return {"valid": False, "canonical": ""}
    return {"valid": True, "canonical": canonical(g)}


# ---------------------------------------------------------------------------
# mahjong (seven pairs / thirteen orphans)
# ---------------------------------------------------------------------------

def classify_mahjong(hand):
    if not isinstance(hand, list) or len(hand) != 14:
        return {"valid": False, "win": False, "pattern": "none"}
    if any(t not in TILE_VOCAB for t in hand):
        return {"valid": False, "win": False, "pattern": "none"}

    from collections import Counter
    cnt = Counter(hand)

    # seven pairs: seven values, each exactly twice
    seven = len(cnt) == 7 and all(v == 2 for v in cnt.values())

    # thirteen orphans
    if set(hand) == TH13 and sum(cnt[t] >= 1 for t in TH13) == 13:
        # 14 tiles, at least 1 of each TH tile → exactly one appears twice
        thirteen = True
    else:
        thirteen = False

    if thirteen:
        return {"valid": True, "win": True, "pattern": "thirteen_orphans"}
    if seven:
        return {"valid": True, "win": True, "pattern": "seven_pairs"}
    return {"valid": True, "win": False, "pattern": "none"}


# ---------------------------------------------------------------------------
# connect (four-in-a-row block)
# ---------------------------------------------------------------------------

_DIRS8 = [(-1, 0), (1, 0), (0, -1), (0, 1),
          (-1, -1), (1, 1), (-1, 1), (1, -1)]


def connect_threat_ends(board):
    rows = len(board)
    if rows == 0:
        return []
    cols = len(board[0])
    for row in board:
        if len(row) != cols:
            return []
    if rows == 0 or cols == 0:
        return []

    ends = set()

    def run(cells):
        # cells: sorted contiguous line of coordinates starting at a "O" cell
        for r, c in cells:
            pass
        return cells

    # scan each of the 4 line directions
    dirs = [(0, 1), (1, 0), (1, 1), (1, -1)]
    for dr, dc in dirs:
        for r in range(rows):
            for c in range(cols):
                # start of a maximal horizontal/vertical/diag run of 'O'
                prev_r, prev_c = r - dr, c - dc
                if 0 <= prev_r < rows and 0 <= prev_c < cols and \
                        board[prev_r][prev_c] == "O":
                    continue
                if board[r][c] != "O":
                    continue
                # collect run
                rr, cc = r, c
                cells = []
                while 0 <= rr < rows and 0 <= cc < cols and board[rr][cc] == "O":
                    cells.append((rr, cc))
                    rr += dr
                    cc += dc
                if len(cells) != 3:
                    continue
                # ends: cells continuing the line at either side
                er, ec = cells[0][0] - dr, cells[0][1] - dc
                if 0 <= er < rows and 0 <= ec < cols and board[er][ec] == ".":
                    ends.add((er, ec))
                er, ec = cells[-1][0] + dr, cells[-1][1] + dc
                if 0 <= er < rows and 0 <= ec < cols and board[er][ec] == ".":
                    ends.add((er, ec))
    # row-major order
    lst = sorted(ends)
    return lst


def solve_connect(board):
    ends = connect_threat_ends(board)
    if not ends:
        return {"block": None, "threats": 0}
    return {"block": list(ends[0]), "threats": len(ends)}


# ---------------------------------------------------------------------------
# maze (shortest-turn navigation)
# ---------------------------------------------------------------------------

def solve_maze(grid, max_turns):
    rows = len(grid)
    if rows == 0:
        return {"reachable": False, "min_turns": -1,
                "within_budget": False, "moves": ""}
    cols = len(grid[0]) if grid else 0
    if rows == 0 or cols == 0:
        return {"reachable": False, "min_turns": -1,
                "within_budget": False, "moves": ""}
    for row in grid:
        if len(row) != cols:
            return {"reachable": False, "min_turns": -1,
                    "within_budget": False, "moves": ""}

    start = goal = None
    for r in range(rows):
        for c in range(cols):
            ch = grid[r][c]
            if ch == "S":
                start = (r, c)
            elif ch == "G":
                goal = (r, c)
    if start is None or goal is None:
        return {"reachable": False, "min_turns": -1,
                "within_budget": False, "moves": ""}

    from collections import deque
    seen = {start}
    prev = {}
    q = deque([start])
    reach_goal = None
    while q:
        cur = q.popleft()
        if cur == goal:
            reach_goal = cur
            break
        r, c = cur
        for step, (dr, dc) in (("U", (-1, 0)), ("D", (1, 0)),
                               ("L", (0, -1)), ("R", (0, 1))):
            nr, nc = r + dr, c + dc
            if not (0 <= nr < rows and 0 <= nc < cols):
                continue
            if grid[nr][nc] == "#":
                continue
            if (nr, nc) in seen:
                continue
            seen.add((nr, nc))
            prev[(nr, nc)] = (cur, step)
            q.append((nr, nc))
    else:
        reach_goal = None

    if reach_goal is None:
        return {"reachable": False, "min_turns": -1,
                "within_budget": False, "moves": ""}

    # rebuild path (a minimal one)
    moves = ""
    cur = goal
    while cur != start:
        pr, step = prev[cur]
        moves = step + moves
        cur = pr
    length = len(moves)
    return {
        "reachable": True,
        "min_turns": length,
        "within_budget": (max_turns is None) or (length <= max_turns),
        "moves": moves,
    }


# ---------------------------------------------------------------------------
# dispatch
# ---------------------------------------------------------------------------

def solve_case(c):
    cid = c.get("id")
    typ = c.get("type")
    if typ == "tiles":
        grid = parse_grid_or_none(c.get("grid"))
        if grid is None:
            result = {"rows": 0, "cols": 0, "solvable": False, "solved": False,
                      "min_moves": -1, "canonical_initial": "",
                      "canonical_goal": "", "states": [], "path": "",
                      "move_count": 0}
        else:
            goal = parse_grid_or_none(c.get("goal"))
            result = solve_tiles(grid, goal)
    elif typ == "snapshot":
        result = solve_snapshot(c.get("grid"))
    elif typ == "mahjong":
        result = classify_mahjong(c.get("hand"))
    elif typ == "connect":
        result = solve_connect(c.get("board"))
    elif typ == "maze":
        result = solve_maze(c.get("grid"), c.get("max_turns"))
    else:
        result = {"error": "unknown_type"}
    out = {"id": cid, "type": typ}
    out.update(result)
    return out


def main(argv):
    inp = argv[1] if len(argv) > 1 else "/app/spec.json"
    out = argv[2] if len(argv) > 2 else "/app/answer.json"
    with open(inp) as f:
        spec = json.load(f)
    cases = spec.get("cases", []) if isinstance(spec, dict) else []
    answers = {}
    for c in cases:
        if isinstance(c, dict) and "id" in c:
            answers[c["id"]] = solve_case(c)
    with open(out, "w") as f:
        json.dump({"answers": answers}, f)


if __name__ == "__main__":
    main(sys.argv)

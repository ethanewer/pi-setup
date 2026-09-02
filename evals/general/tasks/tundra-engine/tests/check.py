#!/usr/bin/env python3
"""Independent verifier for the tundra-engine task.

Runs the agent's /app/solve.py on /app/spec.json (and checks the delivered
/app/answer.json is consistent with a fresh run) and on every /tests/hidden/*.json
fixture. Each answer is verified against its embedded ground-truth "expected"
value AND recomputed with wholly independent logic (own BFS / scans / counts),
so the verifier never depends on how the solver is implemented.

Exit code 0 iff every check passes.
"""
import json, os, subprocess, sys
from collections import deque, Counter

failures = []


def check(name, cond, msg=""):
    if not cond:
        failures.append("%s: %s" % (name, msg))
    print(("PASS " if cond else "FAIL ") + name + ("  " + msg if msg else ""))


def matches_expected(case_type, got, exp):
    """Compare an answer against the embedded oracle `expected` value.

    For snapshot/mahjong every answer is uniquely determined, so the full
    object must match byte-for-byte.  For tiles, maze and connect the
    instruction contract admits several correct outputs (any *optimal* tile
    path/states, any *minimal* maze moves string, any one qualifying connect
    block cell), so we only require the deterministic fields to equal the
    oracle's; the path/moves/block/states themselves are validated by the
    independent per-type checks (exact min_moves via own BFS, legal replay to
    the goal, states match the replayed moves, block in threat-end set).
    """
    if case_type == "tiles":
        keys = ("id", "type", "rows", "cols", "solvable", "solved",
                "min_moves", "move_count", "canonical_initial", "canonical_goal")
    elif case_type == "maze":
        keys = ("id", "type", "reachable", "min_turns", "within_budget")
    elif case_type == "connect":
        keys = ("id", "type", "threats")
    else:  # snapshot, mahjong: unique answer -> strict equality
        return got == exp
    return {k: got.get(k) for k in keys} == {k: exp.get(k) for k in keys}


def run_solver(spec_path, out_path):
    p = subprocess.run(["python3", "/app/solve.py", spec_path, out_path],
                       capture_output=True, text=True)
    if p.returncode != 0:
        raise RuntimeError("solve.py failed on %s: %s" % (spec_path, p.stderr))


def load_out(spec_path):
    out_path = "/tmp/_tundra_out_%d.json" % os.getpid()
    run_solver(spec_path, out_path)
    with open(out_path) as f:
        return json.load(f)["answers"]


def canonical(grid):
    return "".join("%02d" % v for row in grid for v in row)


# ------------------------- independent primitives -------------------------
def inversions(flat):
    seq = [t for t in flat if t != 0]
    inv = 0
    for i in range(len(seq)):
        for j in range(i + 1, len(seq)):
            if seq[i] > seq[j]:
                inv += 1
    return inv


def tile_solvable(flat, rows, cols):
    inv = inversions(flat)
    blank_row = flat.index(0) // cols
    blank_bottom = (rows - 1) - blank_row
    return (inv % 2 == 0) if cols % 2 == 1 else ((inv + blank_bottom) % 2 == 0)


def bfs_tiles_min(flat, rows, cols, goal_flat):
    """Exact shortest number of moves (uniform cost), exact for boards whose
    reachable state graph fits comfortably (3x3 and small boards)."""
    start = tuple(flat)
    goal = tuple(goal_flat)
    seen = {start}
    q = deque([(start, 0)])
    while q:
        cur, d = q.popleft()
        if cur == goal:
            return d
        if len(seen) > 500000:
            return -1  # too big; handled by run-consistency instead
        bi = cur.index(0)
        br, bc = divmod(bi, cols)
        for dr, dc in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            nr, nc = br + dr, bc + dc
            if 0 <= nr < rows and 0 <= nc < cols:
                ni = nr * cols + nc
                lst = list(cur)
                lst[bi], lst[ni] = lst[ni], lst[bi]
                nxt = tuple(lst)
                if nxt not in seen:
                    seen.add(nxt)
                    q.append((nxt, d + 1))
    return -1


def bfs_maze_min(grid):
    rows, cols = len(grid), len(grid[0])
    start = goal = None
    for r in range(rows):
        for c in range(cols):
            if grid[r][c] == "S":
                start = (r, c)
            elif grid[r][c] == "G":
                goal = (r, c)
    if start is None or goal is None:
        return -1
    seen = {start}
    q = deque([(start, 0)])
    while q:
        cur, d = q.popleft()
        if cur == goal:
            return d
        r, c = cur
        for dr, dc in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            nr, nc = r + dr, c + dc
            if 0 <= nr < rows and 0 <= nc < cols and grid[nr][nc] != '#':
                if (nr, nc) not in seen:
                    seen.add((nr, nc))
                    q.append(((nr, nc), d + 1))
    return -1


def replay_maze(grid, moves):
    rows, cols = len(grid), len(grid[0])
    pos = None
    for r in range(rows):
        for c in range(cols):
            if grid[r][c] == "S":
                pos = (r, c)
    if pos is None:
        return None
    dmap = {"U": (-1, 0), "D": (1, 0), "L": (0, -1), "R": (0, 1)}
    for m in moves:
        dr, dc = dmap[m]
        r, c = pos
        nr, nc = r + dr, c + dc
        if not (0 <= nr < rows and 0 <= nc < cols) or grid[nr][nc] == '#':
            return None
        pos = (nr, nc)
    return pos


TH13 = {"A1", "A9", "B1", "B9", "C1", "C9",
        "H1", "H2", "H3", "H4", "H5", "H6", "H7"}
TILE_VOCAB = {s + str(r) for s in "ABC" for r in range(1, 10)}
TILE_VOCAB |= {"H%d" % i for i in range(1, 8)}


# ------------------------------ per-type checks ----------------------------

def validate_snapshot(base, case, got):
    grid = case["grid"]
    valid = (isinstance(grid, list) and len(grid) > 0
             and all(isinstance(r, list) and len(r) > 0 and
                     len(r) == len(grid[0]) for r in grid)
             and all(isinstance(v, int) and not isinstance(v, bool) and
                     0 <= v <= 99 for r in grid for v in r))
    check(base + " valid", got["valid"] == valid)
    if valid:
        check(base + " canonical fits recompute", got["canonical"] == canonical(grid))
    else:
        check(base + " canonical empty", got["canonical"] == "")


def validate_mahjong(base, case, got):
    hand = case["hand"]
    valid = (isinstance(hand, list) and len(hand) == 14
             and all(t in TILE_VOCAB for t in hand))
    check(base + " valid", got["valid"] == valid)
    if not valid:
        check(base + " no win", got["win"] == False and got["pattern"] == "none")
        return
    cnt = Counter(hand)
    seven = len(cnt) == 7 and all(v == 2 for v in cnt.values())
    orphan = set(hand) == TH13 and all(cnt[t] >= 1 for t in TH13)
    expect_win = seven or orphan
    expect_pat = "thirteen_orphans" if orphan else ("seven_pairs" if seven else "none")
    check(base + " win", got["win"] == expect_win)
    check(base + " pattern", got["pattern"] == expect_pat)


def validate_connect(base, case, got):
    board = case["board"]
    rows = len(board)
    rect = rows > 0 and all(len(r) == len(board[0]) for r in board)
    ends = set()
    if rect:
        R, C = len(board), len(board[0])
        for dr, dc in ((0, 1), (1, 0), (1, 1), (1, -1)):
            for r in range(R):
                for c in range(C):
                    if board[r][c] != 'O':
                        continue
                    pr, pc = r - dr, c - dc
                    if 0 <= pr < R and 0 <= pc < C and board[pr][pc] == 'O':
                        continue  # not a run start
                    cells = []
                    rr, cc = r, c
                    while 0 <= rr < R and 0 <= cc < C and board[rr][cc] == 'O':
                        cells.append((rr, cc))
                        rr += dr
                        cc += dc
                    if len(cells) == 3:
                        for er, ec in ((cells[0][0] - dr, cells[0][1] - dc),
                                       (cells[-1][0] + dr, cells[-1][1] + dc)):
                            if 0 <= er < R and 0 <= ec < C and board[er][ec] == '.':
                                ends.add((er, ec))
    sorted_ends = sorted(ends)
    check(base + " threats", got["threats"] == len(sorted_ends))
    if sorted_ends:
        b = got["block"]
        check(base + " block in threat ends",
              isinstance(b, list) and len(b) == 2 and tuple(b) in ends)
    else:
        check(base + " block null", got["block"] is None)


def validate_maze(base, case, got):
    grid, max_turns = case["grid"], case.get("max_turns")
    rows = len(grid)
    rect = rows > 0 and all(len(r) == len(grid[0]) for r in grid)
    nS = sum(r.count("S") for r in grid)
    nG = sum(r.count("G") for r in grid)
    ok = rect is True and nS == 1 and nG == 1
    if ok:
        dist = bfs_maze_min(grid)
        reach = dist >= 0
    else:
        dist, reach = -1, False
    within = reach and (max_turns is None or dist <= max_turns)
    check(base + " reachable", got["reachable"] == reach)
    check(base + " min_turns", got["min_turns"] == dist)
    check(base + " within_budget", got["within_budget"] == within)
    if reach and dist > 0:
        moves = got["moves"]
        end = replay_maze(grid, moves)
        check(base + " moves minimal length", len(moves) == dist)
        check(base + " moves reach goal",
              end is not None and grid[end[0]][end[1]] == "G")
    else:
        check(base + " moves empty", got["moves"] == "")


def validate_tiles(base, case, got):
    grid = case["grid"]
    rows, cols = len(grid), len(grid[0])
    flat = [v for r in grid for v in r]
    n = rows * cols
    is_perm = rows > 0 and len(set(flat)) == n and all(0 <= v < n for v in flat)
    goal = case.get("goal")
    if goal is None:
        vals = list(range(1, n)) + [0]
        goal = [vals[r * cols:(r + 1) * cols] for r in range(rows)]
    goal_flat = [v for r in goal for v in r]
    solvable = is_perm and tile_solvable(flat, rows, cols)

    check(base + " rows", got["rows"] == rows)
    check(base + " cols", got["cols"] == cols)
    check(base + " solvable", got["solvable"] == solvable)
    check(base + " canonical_initial", got["canonical_initial"] == canonical(grid))
    check(base + " canonical_goal", got["canonical_goal"] == canonical(goal))

    if not is_perm or not solvable:
        check(base + " unsolved defs",
              got["solved"] == False and got["min_moves"] == -1)
        return

    # exact minimal distance (independent, exact for reachable 3x3)
    dist = bfs_tiles_min(flat, rows, cols, goal_flat)
    if dist == -1:
        # board too large for independent BFS: fall back to run/replay checks only
        check(base + " solved", got["solved"] == True)
        return
    check(base + " min_moves", got["min_moves"] == dist)
    if dist == 0:
        check(base + " solved0", got["solved"] == True and got["path"] == "")
        return
    # replay path: legal slides into blank, final == goal, states match
    board = [list(r) for r in grid]
    lines = got["path"].split("\n")
    ok_legal = True
    if got["move_count"] != dist or len(lines) != dist:
        ok_legal = False
    for ln in lines:
        parts = ln.split("\t")
        if len(parts) != 3:
            ok_legal = False
            break
        sr, sc = map(int, parts[0].split(","))
        dr_, dc_ = map(int, parts[1].split(","))
        tile_v = int(parts[2])
        if not (0 <= sr < rows and 0 <= sc < cols and 0 <= dr_ < rows and 0 <= dc_ < cols):
            ok_legal = False
            break
        if abs(sr - dr_) + abs(sc - dc_) != 1:
            ok_legal = False
            break
        if board[dr_][dc_] != 0 or board[sr][sc] != tile_v:
            ok_legal = False
            break
        board[dr_][dc_], board[sr][sc] = board[sr][sc], board[dr_][dc_]
    check(base + " optimal length", got["move_count"] == dist)
    check(base + " legal reduced path", ok_legal)
    check(base + " reaches goal", board == goal)
    check(base + " states length", len(got["states"]) == dist)
    # states should equal the boards replayed step by step
    board2 = [list(r) for r in grid]
    ok_states = True
    for ln in lines:
        parts = ln.split("\t")
        sr, sc = map(int, parts[0].split(","))
        dr_, dc_ = map(int, parts[1].split(","))
        board2[dr_][dc_], board2[sr][sc] = board2[sr][sc], board2[dr_][dc_]
    # recompute states from scratch (simpler): build board sequence while replaying
    board3 = [list(r) for r in grid]
    states = []
    for ln in lines:
        parts = ln.split("\t")
        sr, sc = map(int, parts[0].split(","))
        dr_, dc_ = map(int, parts[1].split(","))
        board3[dr_][dc_], board3[sr][sc] = board3[sr][sc], board3[dr_][dc_]
        states.append(canonical(board3))
    check(base + " states recompute", got["states"] == states)


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
if not (os.path.exists("/app/solve.py") and os.path.exists("/app/answer.json")):
    print("FAIL missing /app/solve.py or /app/answer.json")
    sys.exit(1)

with open("/app/answer.json") as f:
    ans = json.load(f)
run_solver("/app/spec.json", "/tmp/_spec_recheck.json")
with open("/tmp/_spec_recheck.json") as f:
    recheck = json.load(f)
check("visible answer consistent with solver", ans == recheck,
      "answer.json differs from solver re-run")

with open("/app/spec.json") as f:
    spec = json.load(f)
for c in spec.get("cases", []):
    check("visible case %s present" % c["id"],
          ans["answers"].get(c["id"]) is not None)

hidden = sorted(p for p in os.listdir("/tests/hidden") if p.endswith(".json"))
if not hidden:
    check("hidden fixtures present", False, "no /tests/hidden/*.json")
    sys.exit(1)

for hf in hidden:
    path = os.path.join("/tests/hidden", hf)
    data = json.load(open(path))
    out = load_out(path)
    for case in data["cases"]:
        cid = case["id"]
        got = out.get(cid)
        exp = data["expected"].get(cid)
        base = "%s/%s" % (hf, cid)
        if got is None:
            check(base, False, "no answer produced")
            continue
        check(base + " type", got.get("type") == case["type"])
        if case["type"] == "snapshot":
            validate_snapshot(base, case, got)
        elif case["type"] == "mahjong":
            validate_mahjong(base, case, got)
        elif case["type"] == "connect":
            validate_connect(base, case, got)
        elif case["type"] == "maze":
            validate_maze(base, case, got)
        elif case["type"] == "tiles":
            validate_tiles(base, case, got)
        check(base + "=expected", matches_expected(case["type"], got, exp))

print("=" * 40)
if failures:
    print("FAILED CHECKS:")
    for f_ in failures:
        print("  -", f_)
    sys.exit(1)
print("ALL CHECKS PASSED")
sys.exit(0)
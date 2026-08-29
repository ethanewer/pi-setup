#!/bin/bash
# drift-upland verifier (executes-deliverable).
# Executes /app/solve.py over every competency (series, meeting, mahjong,
# pursuit, puzzle) on the visible fixtures and on every hidden case in
# /tests/hidden, and replays the /app/moves.txt deliverable. Writes REWARD.
set -u

mkdir -p /logs/verifier

python3 - <<'PY'
import json, os, subprocess, sys
from collections import deque

SOLVE = "/app/solve.py"
EXP = "/tests/expected.json"
HID = "/tests/hidden"

failures = []

# ---------------------------------------------------------------------------
# game model helpers (identical deterministic rules to those documented, but
# implemented from scratch here so the verifier is independent of the oracle)
# ---------------------------------------------------------------------------
_PMV = {"U": (-1, 0), "D": (1, 0), "L": (0, -1), "R": (0, 1), "S": (0, 0)}


def _inb(r, c, R, C):
    return 0 <= r < R and 0 <= c < C


def chaser_move(rows, cols, walls, e, target):
    cands = [(abs(e[0] - target[0]) + abs(e[1] - target[1]), 99, e)]
    for idx, m in enumerate(("U", "D", "L", "R")):
        dr, dc = _PMV[m]
        nr, nc = e[0] + dr, e[1] + dc
        if not _inb(nr, nc, rows, cols) or (nr, nc) in walls:
            continue
        d = abs(nr - target[0]) + abs(nc - target[1])
        cands.append((d, idx, (nr, nc)))
    cands.sort(key=lambda x: (x[0], x[1]))
    cell = cands[0][2]
    if cell == target:
        return None
    return cell


def simulate_pursuit(d, moves):
    rows, cols = d["rows"], d["cols"]
    walls = set(tuple(c) for c in d.get("walls", []))
    P = tuple(d["player"])
    E = tuple(d["opponent"])
    if len(moves) != d["horizon"]:
        return "wrong-move-count: expected %d got %d" % (d["horizon"], len(moves))
    for mv in moves:
        if mv not in _PMV:
            return "unknown-move " + str(mv)
        if P == E:
            return "collision-at-turn-start"
        dr, dc = _PMV[mv]
        np = (P[0] + dr, P[1] + dc)
        if not _inb(np[0], np[1], rows, cols) or np in walls:
            return "illegal-player-cell " + str(np)
        if np == E:
            return "player-walked-onto-chaser"
        ne = chaser_move(rows, cols, walls, E, np)
        if ne is None:
            return "chaser-captured-player"
        P, E = np, ne
    if P == E:
        return "collision-at-end"
    return None  # survived


def puzzle_bfs_depth(start, goal):
    startk = tuple(tuple(r) for r in start)
    goalk = tuple(tuple(r) for r in goal)
    if startk == goalk:
        return 0
    n = len(start)
    dist = {startk: 0}
    q = deque([startk])
    while q:
        st = q.popleft()
        br = bc = None
        for r in range(n):
            for c in range(n):
                if st[r][c] == 0:
                    br, bc = r, c
        for dr, dc in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            nr, nc = br + dr, bc + dc
            if not (0 <= nr < n and 0 <= nc < n):
                continue
            lst = [list(r) for r in st]
            lst[br][bc] = lst[nr][nc]
            lst[nr][nc] = 0
            nk = tuple(tuple(r) for r in lst)
            if nk not in dist:
                dist[nk] = dist[st] + 1
                if nk == goalk:
                    return dist[nk]
                q.append(nk)
    return None  # unsolvable


def replay_puzzle(start, tiles):
    n = len(start)
    board = [list(r) for r in start]
    seen = {tuple(tuple(r) for r in board)}
    for t in tiles:
        # locate tile t and the blank
        tr = tc = br = bc = None
        for r in range(n):
            for c in range(n):
                if board[r][c] == t:
                    tr, tc = r, c
                if board[r][c] == 0:
                    br, bc = r, c
        if abs(tr - br) + abs(tc - bc) != 1:
            return "tile %s not adjacent to blank" % t
        board[tr][tc], board[br][bc] = 0, board[tr][tc]
        k = tuple(tuple(r) for r in board)
        if k in seen:
            return "cycle-detected"
        seen.add(k)
    return board


def run_solve(sub, inp, out):
    if os.path.exists(out):
        os.remove(out)
    r = subprocess.run([sys.executable, SOLVE, sub, inp, out],
                       capture_output=True, text=True, timeout=180)
    if r.returncode != 0:
        return None
    if sub == "puzzle":
        if not os.path.isfile(out):
            return None
        return [int(x) for x in open(out).read().split() if x.strip()]
    try:
        with open(out) as f:
            return json.load(f)
    except Exception:
        return None


# ===========================================================================
# 1. deliverable existence
# ===========================================================================
if not os.path.isfile(SOLVE):
    failures.append("missing /app/solve.py")

exp = json.load(open(EXP)) if os.path.isfile(EXP) else {}
if not os.path.isfile("/app/moves.txt"):
    failures.append("missing /app/moves.txt")

# ===========================================================================
# 2. visible-case execution (each subcommand on the supplied /app fixtures)
# ===========================================================================
if os.path.isfile(SOLVE):
    # series
    got = run_solve("series", "/app/sample_series.json", "/tmp/_v_series.json")
    if got is None or got.get("runs") != exp["series"]["runs"]:
        failures.append("visible series failed: %r" % (got,))

    # meeting
    got = run_solve("meeting", "/app/sample_meeting.json", "/tmp/_v_meet.json")
    if got is None or got.get("venue") != exp["meeting"]["venue"] or \
       got.get("time") != exp["meeting"]["time"]:
        failures.append("visible meeting failed: %r" % (got,))

    # mahjong
    got = run_solve("mahjong", "/app/sample_mahjong.json", "/tmp/_v_mj.json")
    if got is None or got.get("winning_tiles") != exp["mahjong"]["winning_tiles"]:
        failures.append("visible mahjong failed: %r" % (got,))

# ===========================================================================
# 3. deliverable /app/moves.txt : optimal legal slider path for visible puzzle
# ===========================================================================
if os.path.isfile("/app/moves.txt") and os.path.isfile("/app/sample_puzzle.json"):
    pz = json.load(open("/app/sample_puzzle.json"))
    try:
        tiles = [int(x) for x in open("/app/moves.txt").read().split() if x.strip()]
        opt = puzzle_bfs_depth(pz["start"], pz["goal"])
        if opt is None:
            failures.append("visible puzzle unsolvable")
        else:
            if len(tiles) != opt:
                failures.append("moves.txt length %d != optimal %d" % (len(tiles), opt))
            board = replay_puzzle(pz["start"], tiles)
            if isinstance(board, str):
                failures.append("moves.txt illegal: " + board)
            elif board != pz["goal"]:
                failures.append("moves.txt does not reach goal")
    except Exception as e:
        failures.append("moves.txt unreadable: %r" % e)

# ===========================================================================
# 4. hidden cases
# ===========================================================================
def hidden_cases(sub):
    d = os.path.join(HID, sub)
    if not os.path.isdir(d):
        return []
    return sorted(os.listdir(d))

for sub, norm in (("series", "runs"), ("meeting", "venue"), ("mahjong", "winning_tiles")):
    for c in hidden_cases(sub):
        base = os.path.join(HID, sub, c)
        inp = os.path.join(base, "input.json")
        expe = os.path.join(base, "expected.json")
        if not (os.path.isfile(inp) and os.path.isfile(expe)):
            failures.append("hidden %s/%s malformed layout" % (sub, c))
            continue
        got = run_solve(sub, inp, "/tmp/_vh.json")
        if sub == "mahjong":
            ok = (got is not None) and got.get("winning_tiles") == json.load(open(expe))["winning_tiles"]
        elif sub == "series":
            ok = (got is not None) and got.get("runs") == json.load(open(expe))["runs"]
        else:  # meeting
            want = json.load(open(expe))
            ok = (got is not None) and got.get("venue") == want["venue"] and \
                 got.get("time") == want["time"]
        if not ok:
            failures.append("hidden %s/%s failed (got %r)" % (sub, c, got))

# pursuit: verifier simulates the deterministic game for the produced moves
for c in hidden_cases("pursuit"):
    inp = os.path.join(HID, "pursuit", c, "input.json")
    if not os.path.isfile(inp):
        failures.append("hidden pursuit/%s no input" % c)
        continue
    d = json.load(open(inp))
    got = run_solve("pursuit", inp, "/tmp/_vh_p.json")
    if got is None:
        failures.append("hidden pursuit/%s solver error" % c)
        continue
    moves = got.get("moves")
    if not isinstance(moves, list):
        failures.append("hidden pursuit/%s bad schema" % c)
        continue
    err = simulate_pursuit(d, moves)
    if err:
        failures.append("hidden pursuit/%s: %s (moves=%r)" % (c, err, moves))

# puzzle: replay + acyclicity + optimality against independent BFS
for c in hidden_cases("puzzle"):
    inp = os.path.join(HID, "puzzle", c, "input.json")
    if not os.path.isfile(inp):
        failures.append("hidden puzzle/%s no input" % c)
        continue
    d = json.load(open(inp))
    tiles = run_solve("puzzle", inp, "/tmp/_vh_z.txt")
    if tiles is None:
        failures.append("hidden puzzle/%s solver error" % c)
        continue
    opt = puzzle_bfs_depth(d["start"], d["goal"])
    if opt is None:
        failures.append("hidden puzzle/%s unsolvable" % c)
        continue
    if len(tiles) != opt:
        failures.append("hidden puzzle/%s length %d != optimal %d" % (c, len(tiles), opt))
        continue
    board = replay_puzzle(d["start"], tiles)
    if isinstance(board, str):
        failures.append("hidden puzzle/%s illegal: %s" % (c, board))
    elif board != d["goal"]:
        failures.append("hidden puzzle/%s wrong goal" % c)

# ===========================================================================
print("VERIFY FAILURES:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; else reward=0; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0

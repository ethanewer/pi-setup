#!/bin/bash
# drift-upland oracle: writes the /app/solve.py multi-command solver and runs it
# on the visible fixtures to produce the /app/moves.txt deliverable. Never reads /tests.
set -eu

SOLVER=/app/solve.py
cat > "$SOLVER" <<'PY'
"""drift-upland clean-room solver.

Multi-command CLI exercising the bundle competencies:

  series   count contiguous runs of samples staying >= a threshold
  meeting  choose the feasible venue + earliest whole-hour meeting time
  mahjong  list tile completions that turn a 13-tile hand into a winning 14
  pursuit  plan an evasion path that survives a greedy chaser for H turns
  puzzle   emit an optimal minimal sliding-tile path (tiles moved into blank)

Usage: solve.py <subcommand> <input> <output>
"""
import json
import sys
from collections import deque

# ---------------------------------------------------------------------------
# series : contiguous above-threshold run counting
# ---------------------------------------------------------------------------
def do_series(data):
    runs = 0
    cur = 0
    for v in data["series"]:
        if v >= data["threshold"]:
            cur += 1
        else:
            if cur >= data["min_len"]:
                runs += 1
            cur = 0
    if cur >= data["min_len"]:
        runs += 1
    return {"runs": runs}

# ---------------------------------------------------------------------------
# meeting : preference + schedule + commute
# ---------------------------------------------------------------------------
def do_meeting(data):
    duration = 60  # whole-hour slot length in minutes
    best = None    # (start, venue_name)
    for v in data["venues"]:
        name = v["name"]
        cuisine = v["cuisine"]
        lo = v["open_start"]
        hi = v["open_end"]
        ok = True
        for p in data["people"]:
            if cuisine not in p["cuisines"]:
                ok = False
                break
            if name not in p["commute"]:
                ok = False
                break
            lo = max(lo, p["free_start"] + p["commute"][name])
            hi = min(hi, p["free_end"])
        if not ok:
            continue
        latest = hi - 60
        if latest < lo:
            continue
        # earliest whole-hour start (multiple of 60) within [lo, latest]
        s = ((lo + 59) // 60) * 60
        if s > latest:
            continue
        cand = (s, name)
        if best is None or s < best[0] or (s == best[0] and name < best[1]):
            best = cand
    if best is None:
        return {"venue": None, "time": None}
    return {"venue": best[1], "time": best[0]}

# ---------------------------------------------------------------------------
# 3. mahjong : winning-hand completion
# ---------------------------------------------------------------------------
SUITS = ("M", "P", "S")
TILE_TYPES = [su + str(r) for su in SUITS for r in range(1, 10)] + \
             ["E", "S", "W", "N", "R", "G", "B"]  # winds + dragons
TILE_ORDER = {t: i for i, t in enumerate(TILE_TYPES)}


def _can_meld(cnt):
    """True if the multiset decomposes into triplets / sequences.
    Greedy on the smallest present tile: it can only be a triplet of itself or
    the start of a sequence. Counts must total a multiple of 3."""
    total = sum(cnt.values())
    if total == 0:
        return True
    if total % 3 != 0:
        return False
    t = min((x for x in TILE_TYPES if cnt.get(x, 0) > 0), key=TILE_ORDER.get)
    # try triplet
    if cnt.get(t, 0) >= 3:
        c = dict(cnt)
        c[t] -= 3
        if _can_meld(c):
            return True
    # try sequence (suited ranks only)
    if len(t) == 2 and t[0] in SUITS:
        rk = int(t[1])
        if rk + 2 <= 9:
            b = t[0] + str(rk + 1)
            c3 = t[0] + str(rk + 2)
            if cnt.get(b, 0) > 0 and cnt.get(c3, 0) > 0:
                c = dict(cnt)
                c[t] -= 1
                c[b] -= 1
                c[c3] -= 1
                if _can_meld(c):
                    return True
    return False


def _is_win(cnt):
    """14-tile hand: four melds plus one pair."""
    for pair in TILE_TYPES:
        if cnt.get(pair, 0) >= 2:
            rem = dict(cnt)
            rem[pair] -= 2
            if sum(rem.values()) == 12 and _can_meld(rem):
                return True
    return False


def do_mahjong(data):
    hand = data["tiles"]
    if len(hand) != 13:
        return {"winning_tiles": [], "error": "expected 13 tiles"}
    base = {}
    for t in hand:
        if t not in TILE_ORDER:
            return {"winning_tiles": [], "error": "unknown tile " + t}
        base[t] = base.get(t, 0) + 1
    wins = []
    for cand in TILE_TYPES:
        if base.get(cand, 0) >= 4:
            continue
        cnt = dict(base)
        cnt[cand] = cnt.get(cand, 0) + 1
        if _is_win(cnt):
            wins.append(cand)
    wins.sort(key=TILE_ORDER.get)
    return {"winning_tiles": wins}

# ---------------------------------------------------------------------------
# 4. pursuit : evade the deterministic greedy chaser
# ---------------------------------------------------------------------------
_PMV = {"U": (-1, 0), "D": (1, 0), "L": (0, -1), "R": (0, 1), "S": (0, 0)}
_DIRS = {"U": (-1, 0), "D": (1, 0), "L": (0, -1), "R": (0, 1)}


def _in_bounds(r, c, rows, cols):
    return 0 <= r < rows and 0 <= c < cols


def chaser_move(rows, cols, walls, e, target):
    """Deterministic greedy chaser: move to the reachable cell (4-neighbour or
    stay) that minimises Manhattan distance to the target. Ties break by move
    order U,D,L,R then stay. Returns None on capture (lands on the player)."""
    cands = []
    cands.append((abs(e[0] - target[0]) + abs(e[1] - target[1]), 99, e))
    for idx, m in enumerate(("U", "D", "L", "R")):
        dr, dc = _DIRS[m]
        nr, nc = e[0] + dr, e[1] + dc
        if not _in_bounds(nr, nc, rows, cols) or (nr, nc) in walls:
            continue
        d = abs(nr - target[0]) + abs(nc - target[1])
        cands.append((d, idx, (nr, nc)))
    cands.sort(key=lambda x: (x[0], x[1]))
    cell = cands[0][2]
    if cell == target:
        return None
    return cell


def do_pursuit(data):
    rows, cols = data["rows"], data["cols"]
    walls = set(tuple(c) for c in data.get("walls", []))
    hor = data["horizon"]
    P = tuple(data["player"])
    E = tuple(data["opponent"])
    q = deque()
    q.append((P, E, hor, []))
    best_len = 0
    while q:
        p, e, turns, path = q.popleft()
        if turns == 0:
            return {"moves": path}
        for mv in ("U", "D", "L", "R", "S"):
            dr, dc = _PMV[mv]
            np_ = (p[0] + dr, p[1] + dc)
            if not _in_bounds(np_[0], np_[1], rows, cols) or np_ in walls:
                continue
            if np_ == e:
                continue
            ne = chaser_move(rows, cols, walls, e, np_)
            if ne is None:
                continue
            q.append((np_, ne, turns - 1, path + [mv]))
    return {"moves": []}

# ---------------------------------------------------------------------------
# 5. puzzle : optimal sliding-tile path
# ---------------------------------------------------------------------------
def _key(b):
    return tuple(tuple(row) for row in b)


def _blankpos(b):
    for r, row in enumerate(b):
        for c, val in enumerate(row):
            if val == 0:
                return r, c
    raise ValueError("no blank")


def do_puzzle(data):
    start, goal = data["start"], data["goal"]
    n = len(start)
    g = _key(goal)
    parent = {_key(start): None}
    q = deque([_key(start)])
    found = None
    while q:
        st = q.popleft()
        if st == g:
            found = st
            break
        br, bc = _blankpos(st)
        for dr, dc in (-1, 0), (1, 0), (0, -1), (0, 1):
            nr, nc = br + dr, bc + dc
            if not (0 <= nr < n and 0 <= nc < n):
                continue
            lst = [list(r) for r in st]
            tile = lst[nr][nc]
            lst[br][bc] = tile
            lst[nr][nc] = 0
            nxt = tuple(tuple(r) for r in lst)
            if nxt in parent:
                continue
            parent[nxt] = (st, tile)
            q.append(nxt)
    if found is None:
        return {"path": []}
    seq = []
    cur = found
    while parent[cur] is not None:
        prev, tile = parent[cur]
        seq.append(tile)
        cur = prev
    seq.reverse()
    return {"path": seq}


SUBCOMMANDS = {
    "series": do_series,
    "meeting": do_meeting,
    "mahjong": do_mahjong,
    "pursuit": do_pursuit,
    "puzzle": do_puzzle,
}


def main(argv):
    if len(argv) < 4:
        print("usage: solve.py <subcommand> <input> <output>", file=sys.stderr)
        return 2
    sub = argv[1]
    if sub not in SUBCOMMANDS:
        print("unknown subcommand", sub, file=sys.stderr)
        return 2
    with open(argv[2], "r", encoding="utf-8") as fh:
        data = json.load(fh)
    result = SUBCOMMANDS[sub](data)
    if sub == "puzzle":
        with open(argv[3], "w", encoding="utf-8") as fh:
            for t in result["path"]:
                fh.write(str(t) + "\n")
    else:
        with open(argv[3], "w", encoding="utf-8") as fh:
            json.dump(result, fh, indent=2)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
PY

chmod +x "$SOLVER"

# Run the produced solver on the visible fixtures.
python3 "$SOLVER" puzzle /app/sample_puzzle.json /app/moves.txt
python3 "$SOLVER" series /app/sample_series.json /app/sample_series_out.json
python3 "$SOLVER" meeting /app/sample_meeting.json /app/sample_meeting_out.json
python3 "$SOLVER" mahjong /app/sample_mahjong.json /app/sample_mahjong_out.json
python3 "$SOLVER" pursuit /app/sample_pursuit.json /app/sample_pursuit_out.json

echo "solve.sh done: $(ls -1 /app/solve.py /app/moves.txt)"

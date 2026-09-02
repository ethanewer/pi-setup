#!/bin/bash
# tundra-cipher oracle: writes /app/solver.py and runs it on the visible case
# to produce /app/grid.txt, /app/answer.txt, /app/plans.txt. Never reads /tests.
set -eu

SOLVER=/app/solver.py

cat > "$SOLVER" <<'PY'
#!/usr/bin/env python3
"""tundra-cipher clean-room arrangement engine.

Reads a case directory (grid.txt, packs.txt, roster.txt, table.txt) and writes
grid.txt, answer.txt, plans.txt into out_dir.

Usage: solver.py <case_dir> <out_dir>
"""
import sys, os


def parse_hhmm(s):
    h, m = s.split(":")
    return int(h) * 60 + int(m)


def fmt_hhmm(t):
    return "%02d:%02d" % (t // 60, t % 60)


# -------------------------- Sub-problem A: Sudoku --------------------------
def solve_sudoku(givens):
    grid = [list(r) for r in givens]
    rows = [set() for _ in range(9)]
    cols = [set() for _ in range(9)]
    boxes = [set() for _ in range(9)]
    for r in range(9):
        for c in range(9):
            v = grid[r][c]
            if v:
                rows[r].add(v); cols[c].add(v)
                boxes[(r // 3) * 3 + c // 3].add(v)
    empt = [(r, c) for r in range(9) for c in range(9) if grid[r][c] == 0]

    def ok(r, c, v):
        return not (v in rows[r] or v in cols[c] or v in boxes[(r // 3) * 3 + c // 3])

    def bt(k):
        if k == len(empt):
            return True
        r, c = empt[k]
        for v in range(1, 10):
            if ok(r, c, v):
                grid[r][c] = v
                rows[r].add(v); cols[c].add(v); boxes[(r // 3) * 3 + c // 3].add(v)
                if bt(k + 1):
                    return True
                rows[r].discard(v); cols[c].discard(v); boxes[(r // 3) * 3 + c // 3].discard(v)
                grid[r][c] = 0
        return False

    if not bt(0):
        return None
    return grid


# ------------------- Sub-problem B: packing subset count -------------------
def count_packings(cap, weights):
    if cap < 0:
        return 0
    ways = {0: 1}  # ways[s] = number of distinct subsets summing to s
    for w in weights:
        if w <= 0:
            continue
        add = {}
        for s, c in ways.items():
            if s + w <= cap:
                add[s + w] = add.get(s + w, 0) + c
        for s, c in add.items():
            ways[s] = ways.get(s, 0) + c
    return sum(ways.values())


# ------------------- Sub-problem C: schedule candidate slots -------------------
def parse_roster(path):
    raw = []
    with open(path) as fh:
        for ln in fh:
            ln = ln.split("#")[0].strip()
            if ln:
                raw.append(ln.split())
    window = lunch = None
    dur = 15
    days = []
    people = {}  # day -> list[(start, end)]
    for toks in raw:
        if toks[0] == "window":
            window = (parse_hhmm(toks[1]), parse_hhmm(toks[2]))
        elif toks[0] == "lunch":
            lunch = (parse_hhmm(toks[1]), parse_hhmm(toks[2]))
        elif toks[0] == "duration":
            dur = int(toks[1])
        elif toks[0] == "days":
            days = toks[1:]
        elif toks[0] == "person":
            day = toks[2]
            s = parse_hhmm(toks[3]); e = parse_hhmm(toks[4])
            people.setdefault(day, []).append((s, e))
    return {"window": window, "lunch": lunch, "duration": dur,
            "days": days, "people": people}


def scan_slots(roster):
    ws, we = roster["window"]
    ls, le = roster["lunch"]
    dur = roster["duration"]
    slots = []
    for day in roster["days"]:
        t = ws
        while t + dur <= we:
            if t >= le or t + dur <= ls:
                if all(s <= t and e >= t + dur for s, e in roster["people"].get(day, [])):
                    slots.append((day, t))
            t += 15
    return slots


# ------------------- Sub-problem D: round-table neighbour pairs -------------------
def parse_table(path):
    focus = None
    rounds = []
    with open(path) as fh:
        for ln in fh:
            ln = ln.split("#")[0].strip()
            if not ln:
                continue
            toks = ln.split()
            if toks[0] == "focus":
                focus = toks[1]
            elif toks[0] == "round":
                rounds.append(toks[1:])
    return focus, rounds


def neighbor_pairs(focus, rounds):
    pairs = set()
    for rnd in rounds:
        n = len(rnd)
        if n <= 1 or focus not in rnd:
            continue
        i = rnd.index(focus)
        for nb in {rnd[(i - 1) % n], rnd[(i + 1) % n]}:
            if nb != focus:
                pairs.add((focus, nb))
    return sorted(pairs, key=lambda p: p[1])


def main(argv):
    if len(argv) < 3:
        print("usage: solver.py <case_dir> <out_dir>", file=sys.stderr)
        return 2
    case, out = argv[1], argv[2]
    os.makedirs(out, exist_ok=True)

    # grid
    with open(os.path.join(case, "grid.txt")) as fh:
        givens = [[int(x) for x in ln.split()] for ln in fh if ln.strip()]
    grid = solve_sudoku(givens)
    if grid is None:
        return 3
    with open(os.path.join(out, "grid.txt"), "w") as fh:
        fh.write("\n".join(" ".join(str(v) for v in row) for row in grid) + "\n")

    # answer
    with open(os.path.join(case, "packs.txt")) as fh:
        cap = int([ln for ln in fh if ln.strip()][0].split()[0])
    weights = []
    with open(os.path.join(case, "packs.txt")) as fh:
        for idx, ln in enumerate(fh):
            ln = ln.split("#")[0].strip()
            if idx > 0 and ln:
                weights.extend(int(x) for x in ln.split())
    ans = count_packings(cap, weights)
    with open(os.path.join(out, "answer.txt"), "w") as fh:
        fh.write(str(ans))  # no trailing newline

    # plans
    roster = parse_roster(os.path.join(case, "roster.txt"))
    focus, rounds = parse_table(os.path.join(case, "table.txt"))
    with open(os.path.join(out, "plans.txt"), "w") as fh:
        fh.write("[SLOTS]\n")
        for day, t in scan_slots(roster):
            fh.write("%s %s\n" % (day, fmt_hhmm(t)))
        fh.write("[TABLE]\n")
        for a, b in neighbor_pairs(focus, rounds):
            fh.write("%s %s\n" % (a, b))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
PY

chmod +x "$SOLVER"

# Run the real solver on the fixed visible instance to create the visible
# deliverables (never reads /tests).
python3 "$SOLVER" /app/instance /app

echo "solve.sh done: $(ls -1 /app/solver.py /app/grid.txt /app/answer.txt /app/plans.txt)"
#!/bin/bash
# tundra-cipher verifier (executes-deliverable).
#
# Independently recomputes the four expected results (9x9 grid, packing count,
# meeting slots, neighbour pairs) for the visible /app case and for every
# hidden case directory, and compares them with the /app deliverables and with
# what /app/solver.py produces on the hidden cases. Writes reward 0/1.
set -u

mkdir -p /logs/verifier

python3 - <<'PY'
import os, subprocess, sys

SOLVE = "/app/solver.py"
HID = "/tests/hidden"
fail = []

# ---------------------------------------------------------------------------
# independent reference model
# ---------------------------------------------------------------------------
def parse_hhmm(s):
    h, m = s.split(":"); return int(h) * 60 + int(m)

def solve_sudoku(givens):
    grid = [list(r) for r in givens]
    rows = [set() for _ in range(9)]; cols = [set() for _ in range(9)]
    boxes = [set() for _ in range(9)]
    for r in range(9):
        for c in range(9):
            v = grid[r][c]
            if v:
                rows[r].add(v); cols[c].add(v)
                boxes[(r // 3) * 3 + c // 3].add(v)
    empt = [(r, c) for r in range(9) for c in range(9) if grid[r][c] == 0]
    def bt(k):
        if k == len(empt):
            return True
        r, c = empt[k]
        for v in range(1, 10):
            if v in rows[r] or v in cols[c] or v in boxes[(r//3)*3 + c//3]:
                continue
            rows[r].add(v); cols[c].add(v); boxes[(r//3)*3 + c//3].add(v)
            grid[r][c] = v
            if bt(k + 1):
                return True
            rows[r].discard(v); cols[c].discard(v); boxes[(r//3)*3 + c//3].discard(v)
            grid[r][c] = 0
        return False
    return grid if bt(0) else None

def count_packings(cap, weights):
    if cap < 0:
        return 0
    ways = {0: 1}
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

def parse_roster_txt(path):
    raw = []
    for ln in open(path):
        ln = ln.split("#")[0].strip()
        if ln:
            raw.append(ln.split())
    window = lunch = None; dur = 15; days = []; people = {}
    for t in raw:
        if t[0] == "window":         window = (parse_hhmm(t[1]), parse_hhmm(t[2]))
        elif t[0] == "lunch":        lunch = (parse_hhmm(t[1]), parse_hhmm(t[2]))
        elif t[0] == "duration":     dur = int(t[1])
        elif t[0] == "days":         days = t[1:]
        elif t[0] == "person":       people.setdefault(t[2], []).append((parse_hhmm(t[3]), parse_hhmm(t[4])))
    return {"window": window, "lunch": lunch, "duration": dur, "days": days, "people": people}

def expected_slots(path):
    R = parse_roster_txt(path)
    ws, we = R["window"]; ls, le = R["lunch"]; dur = R["duration"]
    out = []
    for day in R["days"]:
        t = ws
        while t + dur <= we:
            if t >= le or t + dur <= ls:
                if all(s <= t and e >= t + dur for s, e in R["people"].get(day, [])):
                    out.append(day + " " + "%02d:%02d" % (t // 60, t % 60))
            t += 15
    return out

def expected_pairs(path):
    focus = None; rounds = []
    for ln in open(path):
        ln = ln.split("#")[0].strip()
        if not ln:
            continue
        t = ln.split()
        if t[0] == "focus":        focus = t[1]
        elif t[0] == "round":      rounds.append(t[1:])
    pairs = set()
    for rnd in rounds:
        n = len(rnd)
        if n <= 1 or focus not in rnd:
            continue
        i = rnd.index(focus)
        for nb in {rnd[(i - 1) % n], rnd[(i + 1) % n]}:
            if nb != focus:
                pairs.add(focus + " " + nb)
    return sorted(pairs)

def grid_givens(path):
    return [[int(x) for x in ln.split()] for ln in open(path) if ln.strip()]

def case_expected(case_dir):
    grid = solve_sudoku(grid_givens(case_dir + "/grid.txt"))
    lines = [ln.split("#")[0].strip() for ln in open(case_dir + "/packs.txt")]
    lines = [ln for ln in lines if ln]
    cap = int(lines[0].split()[0])
    weights = [int(x) for ln in lines[1:] for x in ln.split()]
    ans = count_packings(cap, weights)
    return (grid, str(ans),
            expected_slots(case_dir + "/roster.txt"),
            expected_pairs(case_dir + "/table.txt"))

def read_grid(path):
    g = [ln.split() for ln in open(path) if ln.strip()]
    return [[int(x) for x in row] for row in g] if g else None

def parse_plans(path):
    slots = []; pairs = []; sec = None
    for ln in open(path):
        ln = ln.rstrip("\n")
        if ln == "[SLOTS]":
            sec = "s"; continue
        if ln == "[TABLE]":
            sec = "t"; continue
        if ln == "":
            continue
        if sec == "s":
            slots.append(ln)
        elif sec == "t":
            pairs.append(ln)
    return slots, pairs

def check_grid(name, got, exp):
    if got != exp:
        fail.append(name + ": grid mismatches expected unique solution")
    elif not (isinstance(got, list) and len(got) == 9 and all(len(r) == 9 for r in got)):
        fail.append(name + ": grid not 9x9")

def check_answer(name, got, exp):
    if got is None:
        fail.append(name + ": answer.txt missing")
    elif got != exp:
        fail.append(name + ": answer %r != %r" % (got, exp))
    elif got.endswith("\n"):
        fail.append(name + ": answer.txt has trailing newline")
    elif got != got.rstrip():
        fail.append(name + ": answer.txt has trailing whitespace")

def check_plans(name, slots, pairs, exp_slots, exp_pairs):
    if slots != exp_slots:
        fail.append(name + ": slots mismatch")
    if pairs != exp_pairs:
        fail.append(name + ": pairs mismatch")

# ---------------------------------------------------------------------------
# 1. deliverables exist
# ---------------------------------------------------------------------------
if not os.path.isfile(SOLVE):
    fail.append("missing /app/solver.py")
for d in ("/app/grid.txt", "/app/answer.txt", "/app/plans.txt"):
    if not os.path.isfile(d):
        fail.append("missing " + d)

# ---------------------------------------------------------------------------
# 2. visible case (the /app deliverables)
# ---------------------------------------------------------------------------
exp = case_expected("/app/instance")
if exp[0] is None:
    fail.append("visible: supplied puzzle unexpectedly unsolvable")
if os.path.isfile("/app/grid.txt"):
    check_grid("visible", read_grid("/app/grid.txt"), exp[0])
got_ans = None
if os.path.isfile("/app/answer.txt"):
    got_ans = open("/app/answer.txt", "rb").read().decode()
check_answer("visible", got_ans, exp[1])
if os.path.isfile("/app/plans.txt"):
    check_plans("visible", *parse_plans("/app/plans.txt"), exp[2], exp[3])

# ---------------------------------------------------------------------------
# 3. hidden cases: run /app/solver.py on each and compare
# ---------------------------------------------------------------------------
if os.path.isdir(HID):
    for c in sorted(os.listdir(HID)):
        case_dir = os.path.join(HID, c)
        if not os.path.isdir(case_dir):
            continue
        out = "/tmp/hout_" + c
        os.makedirs(out, exist_ok=True)
        exp = case_expected(case_dir)
        if exp[0] is None:
            fail.append(c + ": hidden puzzle unsolvable (author bug)")
        r = subprocess.run([sys.executable, SOLVE, case_dir, out],
                           capture_output=True, text=True, timeout=200)
        if r.returncode != 0:
            fail.append(c + ": solver error (%s)" % r.stderr.strip()[:120])
            continue
        if os.path.isfile(out + "/grid.txt"):
            check_grid(c, read_grid(out + "/grid.txt"), exp[0])
        got_ans = None
        if os.path.isfile(out + "/answer.txt"):
            got_ans = open(out + "/answer.txt", "rb").read().decode()
        check_answer(c, got_ans, exp[1])
        if os.path.isfile(out + "/plans.txt"):
            check_plans(c, *parse_plans(out + "/plans.txt"), exp[2], exp[3])

print("VERIFY FAILURES: %d" % len(fail))
for f_ in fail:
    print("  -", f_)
sys.exit(1 if fail else 0)
PY

if [ $? -eq 0 ]; then reward=1; else reward=0; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
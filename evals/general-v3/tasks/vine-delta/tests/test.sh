#!/usr/bin/env bash
#
# vine-delta verifier.
# Runs from a pristine container (negative) or after the agent's solve.sh
# (positive). Executes the /app/solve.py deliverable live against visible
# smoke checks and hidden fixtures under /tests/hidden, regenerates
# /app/moves.txt via the deliverable to prove reproducibility, and
# cross-checks the committed moves.txt against an independent replay of the
# canonical session. Writes a numeric reward to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
ok=1
fail(){ echo "FIELD: $*"; ok=0; }
write_py(){ cat > /tmp/vine_check.py; }
left_check(){
  # usage: left_check <label> ; runs the last write_py() buffer as the check
  local label="$1"
  cd /app >/dev/null 2>&1 || { fail "cannot cd /app"; return; }
  if ! PYTHONPATH=/app python3 /tmp/vine_check.py >/tmp/vine_check.log 2>&1; then
    fail "$label"
    tail -3 /tmp/vine_check.log | sed 's/^/   /' >&2
  fi
}

# ---------- A. deliverables present ----------
[ -f /app/solve.py ]  || fail "missing /app/solve.py"
[ -f /app/moves.txt ] || fail "missing /app/moves.txt"

# ---------- B. module + signature + visible smoke ----------
write_py <<'PY'
import solve, inspect, sys
sys.path.insert(0, "/app")
solve = __import__("solve")
assert callable(getattr(solve, "max_quiet_gap", None))
assert callable(getattr(solve, "weighted_return", None))
assert callable(getattr(solve, "solve_sudoku", None))
assert callable(getattr(solve, "play", None))
params = list(inspect.signature(solve.play).parameters)
assert len(params) == 1, "play must take exactly one parameter, got %r" % params
assert solve.max_quiet_gap([2, 3, 5]) == 1
assert abs(solve.weighted_return([0.5, -1.0, 2.0], [2.0, 3.0, 1.0])) < 1e-9
print("visible smoke OK")
PY
left_check "module / signature / visible smoke failed"

# ---------- C. hidden: periodic-scheduling maximum gap ----------
write_py <<'PY'
import json, solve
cases = json.load(open("/tests/hidden/gap/cases.json"))
for i, c in enumerate(cases):
    if c["kind"] == "value":
        got = solve.max_quiet_gap(c["cycles"])
        assert got == c["expect"], "gap[%d]: got %r want %r" % (i, got, c["expect"])
    else:
        try:
            solve.max_quiet_gap(c["cycles"])
            assert False, "gap[%d]: ValueError not raised" % i
        except ValueError:
            pass
print("gap hidden OK (%d cases)" % len(cases))
PY
left_check "C: hidden gap cases failed"

# ---------- D. hidden: weighted-return dot product ----------
write_py <<'PY'
import json, solve
cases = json.load(open("/tests/hidden/weight/cases.json"))
for i, c in enumerate(cases):
    if c["kind"] == "value":
        got = solve.weighted_return(c["w"], c["v"])
        assert abs(got - c["expect"]) < 1e-9, "weight[%d]: got %r want %r" % (i, got, c["expect"])
    else:
        try:
            solve.weighted_return(c["w"], c["v"])
            assert False, "weight[%d]: ValueError not raised" % i
        except ValueError:
            pass
print("weight hidden OK (%d cases)" % len(cases))
PY
left_check "D: hidden weight cases failed"

# ---------- E. hidden: sudoku completion ----------
write_py <<'PY'
import json, glob, solve

def valid(board):
    if len(board) != 9 or any(len(r) != 9 for r in board):
        return False
    for i in range(9):
        if sorted(board[i]) != list(range(1, 10)): return False
        if sorted(board[r][i] for r in range(9)) != list(range(1, 10)): return False
    for br in range(3):
        for bc in range(3):
            box = [board[br*3+i][bc*3+j] for i in range(3) for j in range(3)]
            if sorted(box) != list(range(1, 10)): return False
    return True

cases = sorted(glob.glob("/tests/hidden/sudoku/*.json"))
assert cases, "no hidden sudoku cases"
for f in cases:
    c = json.load(open(f))
    board = [list(c["puzzle"][r*9:(r+1)*9]) for r in range(9)]
    solved = solve.solve_sudoku(board)
    assert solved == [list(c["solved"][r*9:(r+1)*9]) for r in range(9)], "mismatch in " + f
    assert valid(solved), "invalid completion in " + f
try:
    solve.solve_sudoku([[0]*8 for _ in range(9)])
    assert False, "expected ValueError for non-9x9 grid"
except ValueError:
    pass
print("sudoku hidden OK (%d puzzles)" % len(cases))
PY
left_check "E: hidden sudoku cases failed"

# ---------- F. hidden: lane strategy (one legal move per turn) ----------
write_py <<'PY'
import glob, json, solve

def legal_moves(line):
    p = line.split(); n = int(p[0]); cells = p[1]; pos = int(p[2])
    return [i for i in range(n) if i != pos and cells[i] == '.']

class Fake:
    def __init__(self, lines): self.lines = list(lines); self.out = []
    def recv(self): return self.lines.pop(0) if self.lines else ""
    def sendall(self, data):
        s = data.decode() if isinstance(data, bytes) else str(data)
        self.out.append(s.strip())

cases = sorted(glob.glob("/tests/hidden/game/*.json"))
assert cases, "no hidden game cases"
total = 0
for f in cases:
    rows = json.load(open(f))
    fake = Fake([r["line"] for r in rows])
    solve.play(fake)
    assert len(fake.out) == len(rows), (
        "expected exactly one reply per turn in %s (got %d reps for %d turns)"
        % (f, len(fake.out), len(rows)))
    for i, r in enumerate(rows):
        rep = fake.out[i]
        if r["malformed"]:
            assert rep == "ERR", "%s turn %d: malformed -> %r (want ERR)" % (f, i, rep)
            continue
        val = int(rep)
        moves = legal_moves(r["line"])
        if not moves:
            assert val == -1, "%s turn %d: want -1 hold, got %r" % (f, i, val)
        else:
            assert val in moves, "%s turn %d: %r not legal (legal=%r, %s)" % (f, i, val, moves, r["line"])
    total += len(rows)
print("game hidden OK (%d turns / %d cases)" % (total, len(cases)))
PY
left_check "F: hidden game strategy cases failed"

# ---------- G. moves.txt reproducibility + legality ----------
write_py <<'PY'
import solve
fresh = solve.gen_moves()
keep = open("/app/moves.txt").read()
assert fresh == keep, "moves.txt not reproducible (differs from gen_moves())"
session = [
    "3 ... 0", "3 ... 1", "3 .#. 0", "4 .#.. 2",
    "5 ..#.. 1", "2 ## 0", "6 .#.#.. 3", "1 . 0",
]
def reply(line):
    p = line.split(); n = int(p[0]); cells = p[1]; pos = int(p[2])
    legal = [i for i in range(n) if i != pos and cells[i] == '.']
    return str(legal[0]) if legal else "-1"
expected = "\n".join(reply(ln) for ln in session) + "\n"
assert keep == expected, "moves.txt does not match independent canonical replay"
print("moves.txt reproducible + independent replay OK")
PY
left_check "G: moves.txt reproducibility / independent replay failed"

# ---------- reward ----------
[ "$ok" -eq 1 ] && reward=1 || reward=0
echo "$reward" > /logs/verifier/reward.txt
echo "reward=$reward" >&2
exit 0
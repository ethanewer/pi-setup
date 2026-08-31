#!/bin/bash
# onyx-mural verifier (executes-deliverable).
# Checks deliverables, RELOCATES the native binary (so /app/reimpl.py cannot
# delegate to it), then executes /app/reimpl.py on the visible grids and every
# hidden case, comparing stdout byte-for-byte against an independent reference
# implementation (and against the checked-in expected files). Writes REWARD
# (0/1) to /logs/verifier/reward.txt.
set -uo pipefail
mkdir -p /logs/verifier
reward=1
fail(){ echo "FAIL: $*" >&2; reward=0; }

# ---- 0. deliverables present ------------------------------------------ #
[ -f /app/reimpl.py ] || fail "missing /app/reimpl.py"
[ -f /app/notes.md ]  || fail "missing /app/notes.md"
[ -x /app/scene/mural ] || echo "note: native binary already relocated/absent" >&2
[ -d /app/scene ] && mv /app/scene /tmp/.onyx_ref_scene 2>/dev/null
if [ "$reward" -eq 0 ]; then echo "0" >/logs/verifier/reward.txt; echo "final-reward=0"; exit 0; fi

# ---- 1. notes.md must be a substantive write-up of the operation -------- #
if ! grep -qiE 'serpentine|floyd|steinberg|error.?diffus|dither' /app/notes.md; then
  fail "notes.md does not document the discovered operation"
fi

# ---- 2+3. execute /app/reimpl.py on visible + hidden grids ------------- #
PY=$(cat <<'PY'
import glob, os, subprocess, sys

def tdiv(a, b):
    q = abs(a) // abs(b)
    return q if (a >= 0) == (b >= 0) else -q

def ref_mural(text):
    toks = text.split()
    it = iter(toks)
    H = int(next(it)); W = int(next(it))
    px = [[int(next(it)) & 0xFF for _ in range(W)] for _ in range(H)]
    err = [[0] * W for _ in range(H)]
    out = []
    for y in range(H):
        l2r = (y % 2 == 0)
        row = []
        for k in range(W):
            x = k if l2r else (W - 1 - k)
            old = px[y][x] + err[y][x]
            new = 255 if old >= 128 else 0
            e = old - new
            row.append('#' if new == 255 else '.')
            if l2r:
                if x + 1 < W: err[y][x + 1] += tdiv(e * 7, 16)
                if x - 1 >= 0 and y + 1 < H: err[y + 1][x - 1] += tdiv(e * 3, 16)
                if y + 1 < H: err[y + 1][x] += tdiv(e * 5, 16)
                if x + 1 < W and y + 1 < H: err[y + 1][x + 1] += tdiv(e * 1, 16)
            else:
                if x - 1 >= 0: err[y][x - 1] += tdiv(e * 7, 16)
                if x + 1 < W and y + 1 < H: err[y + 1][x + 1] += tdiv(e * 3, 16)
                if y + 1 < H: err[y + 1][x] += tdiv(e * 5, 16)
                if x - 1 >= 0 and y + 1 < H: err[y + 1][x - 1] += tdiv(e * 1, 16)
        out.append(''.join(row))
    return ''.join(r + '\n' for r in out)

fails = []

def run_case(path, want):
    r = subprocess.run([sys.executable, '/app/reimpl.py', path],
                       capture_output=True, timeout=120)
    if r.returncode != 0:
        return f"{path}: reimpl.py rc={r.returncode} ({r.stderr.decode()[:100]})"
    if r.stdout != want.encode():
        return (f"{path}: stdout mismatch (got {len(r.stdout)} bytes, "
                f"want {len(want.encode())})")
    return None

# visible sample grids
vis = sorted(glob.glob('/app/grids/*.txt'))
if not vis:
    fails.append('no visible grids under /app/grids')
for g in vis:
    with open(g) as f:
        text = f.read()
    err = run_case(g, ref_mural(text))
    if err:
        fails.append(err)

# hidden cases: reference AND checked-in expected must both match
cases = sorted(glob.glob('/tests/hidden/case*'))
if not cases:
    fails.append('no hidden cases present')
for d in cases:
    g = os.path.join(d, 'grid.txt')
    exp = os.path.join(d, 'expected.txt')
    if not (os.path.isfile(g) and os.path.isfile(exp)):
        fails.append(f"hidden '{d}' malformed")
        continue
    with open(g) as f:
        text = f.read()
    with open(exp) as f:
        want = f.read()
    if ref_mural(text) != want:
        fails.append(f"hidden '{d}': reference/expected drift (task bug)")
        continue
    err = run_case(g, want)
    if err:
        fails.append(err)

print(" ; ".join(fails) if fails else "HIDDEN-CASES-PASS")
sys.exit(1 if fails else 0)
PY
)
if python3 -c "$PY"; then :; else fail "reimpl functional checks failed"; fi

# ---- finalize ------------------------------------------------------------ #
echo "final-reward=$reward"
echo "$reward" >/logs/verifier/reward.txt
exit 0

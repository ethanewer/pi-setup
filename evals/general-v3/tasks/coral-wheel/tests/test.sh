#!/bin/bash
# Verifier for coral-wheel (executes-deliverable).
# Executes /app/solve.py on the visible input and on every hidden case under
# /tests/hidden, checking the exact result and independently re-deriving the
# optimum. Writes the numeric reward to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
reward=0

if [ -f /app/solve.py ] && [ -f /app/allocation.json ]; then
  if python3 - <<'PY'
import json, os, subprocess

def run_deliverable(inp, out):
    r = subprocess.run(['python3', '/app/solve.py', inp, out],
                       capture_output=True, text=True)
    if r.returncode != 0:
        raise AssertionError('solve.py exited %d: %s'
                             % (r.returncode, r.stderr[:400]))
    with open(out) as f:
        return json.load(f)

def optimum(pf):
    """Independently re-derive the achievable objective
    (return, risk, item_count); None means infeasible. Resource-integer DP."""
    budget, rlim, mret = pf['budget'], pf['risk_limit'], pf['min_return']
    NEG = -10**12
    state = [[[NEG, 10**12] for _ in range(rlim + 1)] for _ in range(budget + 1)]
    state[0][0] = [0, 0]
    for it in pf['items']:
        cost, risk, val = it['cost'], it['risk'], it['return']
        if cost == 0 and risk == 0:
            continue
        for c in range(budget + 1):
            row = state[c]
            for r in range(rlim + 1):
                pc, pr = c - cost, r - risk
                if pc < 0 or pr < 0:
                    continue
                cur = state[pc][pr]
                if cur[0] == NEG:
                    continue
                nr, nc = cur[0] + val, cur[1] + 1
                cell = row[r]
                if cell[0] == NEG or nr > cell[0] or (nr == cell[0] and nc < cell[1]):
                    row[r] = [nr, nc]
    best = None
    for c in range(budget + 1):
        for r in range(rlim + 1):
            val = state[c][r][0]
            if val == NEG or val < mret:
                continue
            cand = (val, r, state[c][r][1])
            if best is None or cand[0] > best[0] or \
               (cand[0] == best[0] and cand[1] < best[1]) or \
               (cand[0] == best[0] and cand[1] == best[1] and cand[2] < best[2]):
                best = cand
    return best

def check(out, expected, pf):
    if expected.get('infeasible'):
        if not out.get('infeasible'):
            raise AssertionError('expected infeasible, output feasible')
        if optimum(pf) is not None:
            raise AssertionError('marked infeasible but a solution exists')
        return
    if out.get('infeasible'):
        raise AssertionError('output infeasible but solution exists')
    if out != expected:
        raise AssertionError('output differs from expected: %r' % (out,))
    # independent optimality re-check
    opt = optimum(pf)
    if opt != (out['return'], out['risk'], out['item_count']):
        raise AssertionError('not optimal: %r vs optimum %r'
                             % ((out['return'], out['risk'], out['item_count']), opt))

# --- visible case ---
vis = run_deliverable('/app/portfolio.json', '/tmp/vis_out.json')
with open('/tests/expected.json') as f:
    vis_exp = json.load(f)
with open('/app/portfolio.json') as f:
    vis_pf = json.load(f)
check(vis, vis_exp, vis_pf)
with open('/app/allocation.json') as f:
    deliv = json.load(f)
check(deliv, vis_exp, vis_pf)

# --- hidden cases ---
for name in sorted(os.listdir('/tests/hidden')):
    hdir = os.path.join('/tests/hidden', name)
    with open(os.path.join(hdir, 'expected.json')) as f:
        exp = json.load(f)
    with open(os.path.join(hdir, 'portfolio.json')) as f:
        pf = json.load(f)
    out = run_deliverable(os.path.join(hdir, 'portfolio.json'), '/tmp/h_out.json')
    check(out, exp, pf)

print('ALL_OK')
PY
  then reward=1
  fi
fi

echo "$reward" > /logs/verifier/reward.txt
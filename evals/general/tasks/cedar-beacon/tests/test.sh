#!/usr/bin/env bash
# Verifier for cedar-beacon numeric pipeline.
# Executes the deliverable /app/solve.py on the visible sample (via the shipped
# answer.json path is NOT enough - it must run on fresh hidden inputs), checks the
# regenerator output file by independently recompiling+running the shipped Fortran,
# greps /app/solve.py for forbidden solver imports, and compares every numeric output
# against an independent reference implementation within rtol.
set -u
mkdir -p /logs/verifier
reward=0
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

python3 - "$work" <<'PY'
import os, sys, json, math, subprocess, glob

work = sys.argv[1]
reward = 1

def fail(msg):
    global reward
    reward = 0
    print("FAIL:", msg, file=sys.stderr)

# ---- independent reference implementations (per the instruction contract) ----
def ref_rk4(lam, init, tmax, steps):
    lam = [float(x) for x in lam]
    y = [float(v) for v in init]
    steps = int(steps)
    h = (float(tmax) / steps) if steps > 0 else 0.0
    def deriv(yv):
        A, B, C = yv
        kA, kB, kC = lam
        return [-kA*A, kA*A - kB*B, kB*B - kC*C]
    peak = sum(y)
    for _ in range(steps):
        k1 = deriv(y)
        k2 = deriv([y[i] + 0.5*h*k1[i] for i in range(3)])
        k3 = deriv([y[i] + 0.5*h*k2[i] for i in range(3)])
        k4 = deriv([y[i] + h*k3[i] for i in range(3)])
        y = [y[i] + (h/6.0)*(k1[i]+2*k2[i]+2*k3[i]+k4[i]) for i in range(3)]
        tot = sum(y)
        if tot > peak:
            peak = tot
    return sum(y), peak

def ref_gamma(fin, leak):
    fin = [float(x) for x in fin]
    leak = float(leak)
    n = len(fin)
    a = [(x + leak) * 1.5 for x in fin]
    b = fin[::-1]
    ramp = [0.0]*n
    for i in range(0, n, 2):
        ramp[i] = fin[i]
    g = [a[i] + b[i] + ramp[i] for i in range(n)]
    scalar = sum(g) + g[0] + g[-1]
    return g, scalar

def ref_risk(values, weights):
    values = [float(x) for x in values]
    n = len(values)
    if n == 0:
        return [], 0.0, 0.0
    if len(weights) != n:
        weights = [1.0]*n
    weights = [float(x) for x in weights]
    mx = max(values)
    ex = [math.exp(v - mx) for v in values]
    tot = sum(ex)
    attn = [e/tot for e in ex]
    return attn, sum(attn), sum(attn[i]*weights[i] for i in range(n))

def close(a, b, rtol=1e-6, atol=1e-9):
    return abs(a - b) <= atol + rtol * abs(b)

# ---- outputs must be finite ----
def finite(x):
    return isinstance(x, (int, float)) and math.isfinite(x)

# 0) deliverable + answer.json present
if not os.path.exists('/app/solve.py'):
    print("FAIL: /app/solve.py missing", file=sys.stderr); reward = 0
    open(os.path.join(work, 'verdict'), 'w').write('0')
    sys.exit(0)
if not os.path.exists('/app/answer.json'):
    fail('/app/answer.json missing (you must run solve.py with no args)')

# 1) forbidden solver imports
src = open('/app/solve.py').read()
for token in ['scipy.integrate', 'from scipy', 'scipy.optimize', 'odeint',
              'solve_ivp', 'sympy', 'torch', 'autograd']:
    if token in src:
        fail("forbidden import token found: %r" % token)
        break

# 2) regenerator: independently recompile the shipped .f90 and rerun it, then diff
try:
    subprocess.run(['gfortran', '/app/src/regen.f90', '-o', os.path.join(work, 'regen_exp')],
                   check=True, capture_output=True)
    subprocess.run([os.path.join(work, 'regen_exp'), os.path.join(work, 'expected_flag.txt')],
                   check=True, capture_output=True)
    expected_flag = open(os.path.join(work, 'expected_flag.txt')).read()
except Exception as e:
    fail('could not rebuild/run regenerator reference: %s' % e); expected_flag = None

flag_path = '/app/derived/flag.txt'
if expected_flag is not None:
    if not os.path.exists(flag_path):
        fail('regenerator output %s missing' % flag_path)
    else:
        got_flag = open(flag_path).read()
        if len(got_flag.strip()) == 0:
            fail('regenerator output is empty')
        elif got_flag != expected_flag:
            fail('regenerator output does not match the compiled program output')

# 3) per-hidden-case numeric verification
cases = sorted(glob.glob('/tests/hidden/*.json'))
if not cases:
    fail('no hidden cases found')
for case_path in cases:
    case = json.load(open(case_path))
    out_path = os.path.join(work, 'out_' + os.path.basename(case_path))
    r = subprocess.run([sys.executable, '/app/solve.py', case_path, out_path],
                       capture_output=True)
    if r.returncode != 0 or not os.path.exists(out_path):
        fail('solve.py crashed/exited non-zero on %s (%s)' %
             (case_path, r.stderr.decode()[-300:]))
        continue
    out = json.load(open(out_path))

    ode = case['ode']
    try:
        fref, pref = ref_rk4(ode['lam'], ode['init'], ode['tmax'], ode['steps'])
        fgot = out['ode']['final_total']; pgot = out['ode']['peak_total']
        if not (finite(fgot) and close(fgot, fref)):
            fail('%s: final_total mismatch got=%r ref=%r' % (case['id'], fgot, fref))
        if not (finite(pgot) and close(pgot, pref)):
            fail('%s: peak_total mismatch got=%r ref=%r' % (case['id'], pgot, pref))
    except Exception as e:
        fail('%s: ODE check error %s' % (case['id'], e))

    gf = case['gamma']
    try:
        gref_arr, gref_scalar = ref_gamma(gf['fin'], gf['leak'])
        garr = out['gamma']['array']; gsc = out['gamma']['scalar']
        if len(garr) != len(gref_arr):
            fail('%s: gamma array length got=%d ref=%d' %
                 (case['id'], len(garr), len(gref_arr)))
        else:
            for i in range(len(gref_arr)):
                if not (finite(garr[i]) and close(garr[i], gref_arr[i])):
                    fail('%s: gamma[%d] mismatch' % (case['id'], i)); break
        if not (finite(gsc) and close(gsc, gref_scalar)):
            fail('%s: gamma scalar mismatch got=%r ref=%r' % (case['id'], gsc, gref_scalar))
    except Exception as e:
        fail('%s: gamma check error %s' % (case['id'], e))

    rv = case['risk']
    try:
        val = rv.get('values', []); wgt = rv.get('weights', [])
        aref, asum_ref, score_ref = ref_risk(val, wgt)
        attn = out['risk']['attn']; attn_sum = out['risk']['attn_sum']; score = out['risk']['score']
        if attn_sum == 0.0 and len(val) > 0:
            pass
        if len(attn) != len(aref):
            fail('%s: risk attn length got=%d ref=%d' % (case['id'], len(attn), len(aref)))
        else:
            for i in range(len(aref)):
                if not (finite(attn[i]) and close(attn[i], aref[i])):
                    fail('%s: risk attn[%d] mismatch' % (case['id'], i)); break
        if not finite(attn_sum) or abs(attn_sum - asum_ref) > 1e-9:
            fail('%s: attn_sum got=%r ref=%r' % (case['id'], attn_sum, asum_ref))
        if not (finite(score) and close(score, score_ref)):
            fail('%s: risk score got=%r ref=%r' % (case['id'], score, score_ref))
        # normalized attention for every non-empty bag
        if len(val) > 0 and abs(attn_sum - 1.0) > 1e-9:
            fail('%s: attention not normalized attn_sum=%r' % (case['id'], attn_sum))
    except Exception as e:
        fail('%s: risk check error %s' % (case['id'], e))

open(os.path.join(work, 'verdict'), 'w').write(str(reward))
PY

verdict=$(cat "$work/verdict" 2>/dev/null || echo "0")
if [ "$verdict" = "1" ]; then
  reward=1
else
  reward=0
fi
echo "$reward" > /logs/verifier/reward.txt
echo "reward=$reward" >&2
exit 0

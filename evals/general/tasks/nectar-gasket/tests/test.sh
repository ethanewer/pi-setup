#!/usr/bin/env bash
# Verifier for nectar-gasket (garden ODE integrator + spectral tools).
# Executes /app/integrate.py on the hidden ODE cases and the ensemble, executes
# /app/eig.py on the hidden eigen cases (including a 1400x1400 fixture), checks the
# shipped /app/metrics.json report, and compares everything against independent
# fine-grained reference recomputations. Writes reward to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
reward=0
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

python3 - "$work" <<'PY'
import os, sys, json, math, glob, subprocess
math_isfinite = math.isfinite
import numpy as np
from scipy.integrate import solve_ivp
from scipy.linalg import eigvals

work = sys.argv[1]
reward = 1

def fail(msg):
    global reward
    reward = 0
    print("FAIL:", msg, file=sys.stderr)

# ---------------------------------------------------------------------------
# Independent reference implementations (per the instruction contract)
# ---------------------------------------------------------------------------
def ref_traj(ode):
    a = np.array(ode['a'], float); alpha = np.array(ode['alpha'], float)
    cs = np.array(ode['c'], float); eps = float(ode['eps']); y0 = np.array(ode['y0'], float)
    def rhs(t, y):
        y = np.asarray(y, float)
        d = y[None, :] - y[:, None]
        F = d / (d * d + eps * eps)
        np.fill_diagonal(F, 0.0); S = F.sum(axis=1)
        return alpha * (a - y) - cs * S
    t0 = float(ode['t0']); tmax = float(ode['tmax']); M = int(ode['M'])
    tm = np.linspace(t0, tmax, M)
    sol = solve_ivp(rhs, [t0, tmax], y0, rtol=1e-12, atol=1e-14,
                    method='DOP853', dense_output=True)
    return np.array([sol.sol(t) for t in tm])

def ref_phys(states, a):
    a = np.array(a, float)
    cl = float(np.max(np.abs(a[:, None] - a[None, :]))) if a.size > 1 else 1.0
    st = np.asarray(states, float)
    if st.shape[1] < 2:
        return float('inf'), float('inf')
    tot = 0.0; cnt = 0; mn = float('inf')
    for row in st:
        D = np.abs(row[:, None] - row[None, :]); np.fill_diagonal(D, np.inf)
        vals = D[np.isfinite(D)]
        if vals.size:
            mn = min(mn, float(vals.min())); tot += float(vals.sum()); cnt += vals.size
    return (mn / cl) if cl > 0 else float('inf'), ((tot / cnt) / cl) if cnt and cl > 0 else float('inf')

def ref_dominant(A):
    w = eigvals(np.array(A, float))
    o = np.lexsort((np.abs(np.imag(w)), -np.real(w), -np.abs(w)))
    return complex(w[o[0]])

# ---------------------------------------------------------------------------
# 0) Deliverables present / executable
# ---------------------------------------------------------------------------
for f in ['/app/integrate.py', '/app/eig.py']:
    if not os.path.isfile(f):
        fail('%s missing' % f)
        open(os.path.join(work, 'verdict'), 'w').write('0'); sys.exit(0)
    if not os.access(f, os.X_OK):
        fail('%s not executable' % f)
if not os.path.isfile('/app/metrics.json'):
    fail('/app/metrics.json missing (must be produced by running the ensemble)')

# ---------------------------------------------------------------------------
# 1) integrate hidden cases: accuracy + budget + physics metrics
# ---------------------------------------------------------------------------
hidden = sorted(glob.glob('/tests/hidden/*.json'))
if not hidden:
    fail('no hidden cases found')
for hp in hidden:
    case = json.load(open(hp))
    if 'ode' not in case and 'integrate_cases' not in case:
        continue
    odes = case['integrate_cases'] if 'integrate_cases' in case else [case['ode']]
    for idx, ode in enumerate(odes):
        tag = '%s[%d]' % (case.get('id', os.path.basename(hp)), idx)
        inc = os.path.join(work, 'in.json'); outc = os.path.join(work, 'out.json')
        json.dump({'id': tag, 'ode': ode}, open(inc, 'w'))
        r = subprocess.run([sys.executable, '/app/integrate.py', 'trajectory', inc, outc],
                           capture_output=True)
        if r.returncode != 0 or not os.path.exists(outc):
            fail('%s: integrate.py crashed/non-zero (%s)' % (tag, r.stderr.decode()[-250:]))
            continue
        got = json.load(open(outc))
        rref = ref_traj(ode)
        gs = np.asarray(got['states'], float)
        if gs.shape != rref.shape:
            fail('%s: states shape %s != ref %s' % (tag, gs.shape, rref.shape))
        else:
            err = float(np.max(np.abs(gs - rref)))
            tol = float(ode['tol'])
            if err > tol:
                fail('%s: max-abs error %.3e > tol %.2e' % (tag, err, tol))
        if got['eval_count'] > int(ode['budget']):
            fail('%s: eval_count %d > budget %d' % (tag, got['eval_count'], ode['budget']))
        thr = ode.get('thresholds', {})
        m = got.get('metrics', {})
        if not m.get('finite'):
            fail('%s: reported metrics not finite' % tag)
        if int(ode['n']) >= 2:
            mnd, avd = m.get('min_norm_dist'), m.get('avg_norm_dist')
            if not isinstance(mnd, (int, float)) or not (mnd >= thr.get('min_norm_dist', 0)):
                fail('%s: min_norm_dist %s below threshold' % (tag, mnd))
            if not isinstance(avd, (int, float)) or not (avd >= thr.get('avg_norm_dist', 0)):
                fail('%s: avg_norm_dist %s below threshold' % (tag, avd))
            rmn, rav = ref_phys(rref, ode['a'])
            if not (rmn >= thr.get('min_norm_dist', 0)):
                fail('%s: reference min_norm_dist %.3e below threshold' % (tag, rmn))
        else:
            if m.get('min_norm_dist') != float('inf') and not os.path.exists(outc):
                fail('%s: singleton physics not vacuous' % tag)

# ---------------------------------------------------------------------------
# 2) ensemble: real multiprocessing + serial/parallel consistency + timing
# ---------------------------------------------------------------------------
ens_in = '/app/sample_garden.json'
ens_out = os.path.join(work, 'ens.json')
r = subprocess.run([sys.executable, '/app/integrate.py', 'ensemble', ens_in, ens_out],
                   capture_output=True, timeout=300)
if r.returncode != 0 or not os.path.exists(ens_out):
    fail('ensemble crashed (%s)' % r.stderr.decode()[-250:])
else:
    e = json.load(open(ens_out))
    nj = int(e.get('n_jobs', -1))
    preq = int(json.load(open(ens_in))['ensemble']['n_jobs'])
    if nj != preq:
        fail('ensemble n_jobs %s != requested %s' % (nj, preq))
    sp = e['sequential']; pp = e['parallel']
    if sp.get('distinct_pids') != 1:
        fail('sequential distinct_pids=%s (should be 1)' % sp.get('distinct_pids'))
    if pp.get('distinct_pids', 0) < 2:
        fail('parallel distinct_pids=%s, parallel not real (use >1 process)' % pp.get('distinct_pids'))
    md = e.get('max_parallel_serial_abs_diff')
    if not isinstance(md, (int, float)) or md > 1e-6:
        fail('serial/parallel differ: max_abs_diff=%s' % md)
    for key in ('seconds',):
        for sec in (sp, pp):
            v = sec.get(key)
            if not (isinstance(v, (int, float)) and math_isfinite(v) and v > 0):
                fail('ensemble %s.%s not a finite positive number (%r)' % (sec is sp and 'seq' or 'par', key, v))
    for label, sec in (('sequential', sp), ('parallel', pp)):
        a = sec.get('min_norm_dist'); b = sec.get('avg_norm_dist')
        if not (isinstance(a, (int, float)) and a > 0 and math_isfinite(a)):
            fail('ensemble %s.min_norm_dist invalid' % label)
        if not (isinstance(b, (int, float)) and b > 0 and math_isfinite(b)):
            fail('ensemble %s.avg_norm_dist invalid' % label)
    if abs(float(sp['min_norm_dist']) - float(pp['min_norm_dist'])) > 0.01:
        fail('parallel/serial min_norm mismatch')
    if abs(float(sp['avg_norm_dist']) - float(pp['avg_norm_dist'])) > 0.01:
        fail('parallel/serial avg_norm mismatch')
    spd = e.get('speedup')
    if not (isinstance(spd, (int, float)) and math_isfinite(spd) and spd > 0):
        fail('speedup not a finite positive number')

# ---------------------------------------------------------------------------
# 3) metrics.json report keys
# ---------------------------------------------------------------------------
mj = json.load(open('/app/metrics.json'))
for path in (['sequential', 'seconds'], ['parallel', 'seconds'], ['speedup']):
    node = mj
    for key in path:
        node = node.get(key)
    if not (isinstance(node, (int, float)) and math_isfinite(node) and node > 0):
        fail('metrics.json %s not a finite positive number' % '.'.join(path))

# ---------------------------------------------------------------------------
# 4) eig hidden scenarios: dominant + principal-minor row
# ---------------------------------------------------------------------------
for hp in hidden:
    case = json.load(open(hp))
    for e in case.get('eig', []):
        tag = '%s/%s' % (case.get('id', os.path.basename(hp)), e.get('name', '?'))
        if 'file' in e:
            A = np.load(e['file']).astype(float)
            inp = {'file': e['file'], 'do_pm': e.get('do_pm', False)}
        else:
            A = np.asarray(e['matrix'], float)
            inp = {'matrix': e['matrix'], 'do_pm': e.get('do_pm', False)}
        ip = os.path.join(work, 'e_in.json'); op = os.path.join(work, 'e_out.json')
        json.dump(inp, open(ip, 'w'))
        r = subprocess.run([sys.executable, '/app/eig.py', ip, op], capture_output=True)
        if r.returncode != 0 or not os.path.exists(op):
            fail('%s: eig.py crashed/non-zero (%s)' % (tag, r.stderr.decode()[-250:]))
            continue
        got = json.load(open(op))
        dref = ref_dominant(A); dgot = complex(*got['dominant'])
        if abs(dref - dgot) > 1e-6:
            fail('%s: dominant got %s ref %s' % (tag, dgot, dref))
        if e.get('do_pm'):
            pm = got.get('principal_minor_spectra', [])
            if not isinstance(pm, list) or len(pm) != A.shape[0]:
                fail('%s: principal_minor_spectra length %s != %d' % (tag, len(pm), A.shape[0]))
            else:
                for j in range(A.shape[0]):
                    rj = ref_dominant(A[:j + 1, :j + 1])
                    if abs(rj - complex(pm[j][0], pm[j][1])) > 1e-6:
                        fail('%s: principal-minor[%d] %s vs %s' % (tag, j, pm[j], rj))
                        break

open(os.path.join(work, 'verdict'), 'w').write(str(reward))
PY

verdict=$(cat "$work/verdict" 2>/dev/null || echo "0")
if [ "$verdict" = "1" ]; then reward=1; else reward=0; fi
echo "$reward" > /logs/verifier/reward.txt
echo "reward=$reward" >&2
exit 0
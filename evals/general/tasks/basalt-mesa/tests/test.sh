#!/bin/bash
# Verifier for basalt-mesa: enforces the no-modify rule on the supplied /app
# fixtures, EXECUTES /app/solve.py on the visible data and on every hidden
# dataset in /tests/hidden, checks structure + fitted coefficients against an
# in-process reference, and runs the KS resampling test. Writes REWARD (0/1)
# to /logs/verifier/reward.txt. Never crashes on malformed agent output.
set -u

mkdir -p /logs/verifier

PRISTINE_OBS_SHA="89d0e1a5f2b0861b8eaad226b9ac6573d267c8230699c961212a4b269c13b33f"
PRISTINE_DAG_SHA="aad206803ccbb82918c676937b52d163f50012025f08147b75697d5239cc6476"

no_modify_broken=0
if [ ! -f /app/obs.csv ] || [ ! -f /app/dag.json ]; then
    echo "no-modify: visible fixtures missing" >&2
    no_modify_broken=1
else
    o=$(sha256sum /app/obs.csv | awk '{print $1}')
    d=$(sha256sum /app/dag.json | awk '{print $1}')
    [ "$o" = "$PRISTINE_OBS_SHA" ] || { echo "no-modify: obs.csv modified" >&2; no_modify_broken=1; }
    [ "$d" = "$PRISTINE_DAG_SHA" ] || { echo "no-modify: dag.json modified" >&2; no_modify_broken=1; }
fi

cat > /tmp/bm_check.py <<'PY'
import json, os, shutil, subprocess, sys, tempfile
import numpy as np

KS_MAX = 0.035
SIM_M = 20000
SIM_SEED = 20260210
failures = []


def load_matrix(obs_path, cols):
    raw = np.genfromtxt(obs_path, delimiter=',', names=True)
    return np.vstack([np.asarray(raw[c], dtype=float) for c in cols]).T


def reference_edges(X, cols, root):
    n = len(cols)
    C = np.corrcoef(X, rowvar=False)
    in_tree = [0]
    edges = []
    rest = [i for i in range(n) if i != 0]
    while rest:
        best = None
        for i in in_tree:
            for j in rest:
                key = (-abs(C[i, j]), min(i, j), max(i, j))
                if best is None or key < best[0]:
                    best = (key, i, j)
        _, i, j = best
        edges.append((i, j))
        in_tree.append(j)
        rest.remove(j)
    children = {i: [] for i in range(n)}
    for (i, j) in edges:
        children[i].append(j)
        children[j].append(i)
    ri = cols.index(root)
    seen = {ri}
    out = []
    queue = [ri]
    while queue:
        u = queue.pop(0)
        for v in children[u]:
            if v not in seen:
                seen.add(v)
                out.append((u, v))
                queue.append(v)
    return out


def ks2(a, b):
    a = np.sort(np.asarray(a, dtype=float))
    b = np.sort(np.asarray(b, dtype=float))
    allv = np.concatenate([a, b])
    cdfa = np.searchsorted(a, allv, side='right') / len(a)
    cdfb = np.searchsorted(b, allv, side='right') / len(b)
    return float(np.max(np.abs(cdfa - cdfb)))


def run_solver(obs, dag, outdir):
    env = dict(os.environ)
    try:
        r = subprocess.run(['python3', '/app/solve.py', obs, dag, outdir],
                           capture_output=True, text=True, timeout=240, env=env)
    except Exception as e:
        return False, 'solver raised %s' % e
    if r.returncode != 0:
        return False, 'solver exited %d: %s' % (r.returncode, r.stderr[-300:])
    return True, ''


def read_fit(path, ncols_expected):
    if not os.path.isfile(path):
        raise ValueError('missing %s' % path)
    rows = {}
    lines = open(path).read().splitlines()
    if not lines or lines[0].strip() != 'parent,child,intercept,slope,sigma':
        raise ValueError('bad header in %s' % path)
    for line in lines[1:]:
        if not line.strip():
            continue
        parts = line.split(',')
        if len(parts) != 5:
            raise ValueError('malformed row %r' % line)
        p, c = parts[0], parts[1]
        rows[(p, c)] = tuple(float(x) for x in parts[2:5])
    return rows


def check_case(obs, dag_path, outdir, label):
    dag = json.load(open(dag_path))
    cols = dag['network_columns']
    root = dag['root']
    X = load_matrix(obs, cols)
    ref_edges = reference_edges(X, cols, root)
    try:
        got_lines = open(os.path.join(outdir, 'recovered_edges.csv')).read().splitlines()
        if not got_lines or got_lines[0].strip() != 'parent,child':
            raise ValueError('bad recovered_edges.csv header')
        got = set()
        for line in got_lines[1:]:
            if line.strip():
                parts = line.split(',')
                if len(parts) != 2:
                    raise ValueError('malformed edge %r' % line)
                got.add((parts[0], parts[1]))
    except Exception as e:
        failures.append('%s: %s' % (label, e))
        return
    ref_set = set((cols[i], cols[j]) for i, j in ref_edges)
    if got != ref_set:
        failures.append('%s: recovered edges mismatch' % label)
        return
    # coefficient fit check
    try:
        fit = read_fit(os.path.join(outdir, 'network_fit.csv'), len(ref_edges))
    except Exception as e:
        failures.append('%s: %s' % (label, e))
        return
    for (i, j) in ref_edges:
        p_, c_ = X[:, i], X[:, j]
        slope = np.cov(p_, c_, ddof=0)[0, 1] / np.var(p_)
        inter = c_.mean() - slope * p_.mean()
        resid = c_ - (inter + slope * p_)
        sig = float(np.sqrt(np.mean(resid ** 2)))
        key = (cols[i], cols[j])
        if key not in fit:
            failures.append('%s: missing fit row %s' % (label, key))
            return
        gi, gs, gsg = fit[key]
        for name, ref, gv in (('intercept', inter, gi), ('slope', slope, gs),
                              ('sigma', sig, gsg)):
            if abs(gv - ref) > max(1e-4, 5e-4 * abs(ref)):
                failures.append('%s: %s %s off: %g vs %g' % (label, key[1], name, gv, ref))
                return
    # root fit check
    try:
        lines = open(os.path.join(outdir, 'root_fit.csv')).read().splitlines()
        if len(lines) < 2 or lines[0].strip() != 'node,mu,sigma':
            raise ValueError('bad root_fit.csv')
        parts = lines[1].split(',')
        if len(parts) != 3 or parts[0] != root:
            raise ValueError('bad root_fit.csv row')
        rmu, rsd = float(parts[1]), float(parts[2])
    except Exception as e:
        failures.append('%s: %s' % (label, e))
        return
    ri = cols.index(root)
    if abs(rmu - X[:, ri].mean()) > 1e-3 or abs(rsd - X[:, ri].std()) > 1e-3:
        failures.append('%s: root parameters off' % label)
        return
    # KS resampling test from the agent's own parameters
    rng = np.random.default_rng(SIM_SEED)
    sim = {root: rng.normal(rmu, rsd, SIM_M)}
    for (i, j) in ref_edges:
        gi, gs, gsg = fit[(cols[i], cols[j])]
        sim[cols[j]] = gi + gs * sim[cols[i]] + rng.normal(0, gsg, SIM_M)
    for k, c in enumerate(cols):
        d = ks2(sim[c], X[:, k])
        if d > KS_MAX:
            failures.append('%s: KS %s = %.4f > %.3f' % (label, c, d, KS_MAX))
            return
    print('OK(%s): maxKS=%.4f' % (label, max(ks2(sim[c], X[:, k]) for k, c in enumerate(cols))))


def main():
    if not os.path.isfile('/app/solve.py'):
        failures.append('missing /app/solve.py')
    if not failures:
        if os.path.isfile('/app/obs.csv') and os.path.isfile('/app/dag.json'):
            # visible deliverables must exist and match the reference
            need = ['/app/recovered_edges.csv', '/app/network_fit.csv',
                    '/app/root_fit.csv']
            if not all(os.path.isfile(f) for f in need):
                failures.append('missing visible deliverables in /app')
            else:
                check_case('/app/obs.csv', '/app/dag.json', '/app', 'visible')
        else:
            failures.append('visible fixtures missing')
    if not failures:
        hd = '/tests/hidden'
        cases = sorted(os.listdir(hd)) if os.path.isdir(hd) else []
        if not cases:
            failures.append('no hidden cases')
        for c in cases:
            base = os.path.join(hd, c)
            if not all(os.path.isfile(os.path.join(base, f))
                       for f in ('obs.csv', 'dag.json')):
                failures.append('hidden %s malformed' % c)
                continue
            outdir = tempfile.mkdtemp(prefix='bm_%s_' % c)
            ok, msg = run_solver(os.path.join(base, 'obs.csv'),
                                 os.path.join(base, 'dag.json'), outdir)
            if not ok:
                failures.append('hidden %s: %s' % (c, msg))
            else:
                check_case(os.path.join(base, 'obs.csv'),
                           os.path.join(base, 'dag.json'), outdir, c)
            shutil.rmtree(outdir, ignore_errors=True)
    for f in failures:
        print('FAIL: %s' % f)
    print('verify failures: %d' % len(failures))
    return 1 if failures else 0


sys.exit(main())
PY

BM=0
if python3 /tmp/bm_check.py; then BM=1; fi
if [ "$no_modify_broken" = "1" ]; then BM=0; fi

echo "$BM" > /logs/verifier/reward.txt
exit 0

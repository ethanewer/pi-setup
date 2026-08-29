#!/usr/bin/env bash
# Oracle for nectar-gasket: writes the real /app/integrate.py (garden ODE
# integrator + serial/parallel ensemble runner) and /app/eig.py (dominant
# eigenvalue + principal-minor spectra), then RUNS them on the shipped data to
# produce /app/metrics.json and demonstration outputs. Never reads /tests.
set -eu

cat > /app/integrate.py <<'PY'
#!/usr/bin/env python3
"""Nectar Gasket orbital-garden integrator.

Implements the "Garden" coupled relaxation ODE, a real fixed-step RK4 integrator
that self-selects its step against the per-case accuracy target under a hard
RHS-evaluation budget, physics metrics (normalized min/avg pair distance), and a
serial/parallel ensemble runner over per-k randomized initial-state subsamples.
"""
import sys, os, json, time
import numpy as np
from concurrent.futures import ProcessPoolExecutor

# ----------------------------------------------------------------------------
# The documented ODE -- "garden" family
#   du_i/dt = alpha_i*(a_i - u_i) - c_i * sum_{j != i} (u_j-u_i)/((u_j-u_i)^2+eps^2)
# ----------------------------------------------------------------------------
def rhs(y, a, alpha, c, eps):
    d = y[None, :] - y[:, None]                 # d[i,j] = u_j - u_i
    with np.errstate(divide='ignore', invalid='ignore'):
        F = d / (d * d + eps * eps)
    np.fill_diagonal(F, 0.0)
    S = F.sum(axis=1)
    return alpha * (a - y) - c * S

def rk4_full(y0, h, steps, a, alpha, cc, eps):
    y = np.array(y0, float).copy()
    n = y.size
    arr = (np.asarray(a, float), np.asarray(alpha, float), np.asarray(cc, float), float(eps))
    out = np.empty((steps + 1, n))
    out[0] = y
    for k in range(steps):
        k1 = rhs(y, *arr)
        k2 = rhs(y + 0.5 * h * k1, *arr)
        k3 = rhs(y + 0.5 * h * k2, *arr)
        k4 = rhs(y + h * k3, *arr)
        y = y + (h / 6.0) * (k1 + 2 * k2 + 2 * k3 + k4)
        out[k + 1] = y
    return out, 4 * n * steps

def char_len(a):
    a = np.asarray(a, float)
    if a.size < 2:
        return 1.0
    return float(np.max(np.abs(a[:, None] - a[None, :])))

def physics_metrics(states, a):
    states = np.asarray(states, float)
    cl = 1.0 if np.asarray(a).size < 2 else char_len(a)
    fin = bool(np.all(np.isfinite(states)))
    if states.shape[1] < 2:
        return {'min_norm_dist': float('inf'), 'avg_norm_dist': float('inf'),
                'char_len': cl, 'finite': fin}
    tot = 0.0; cnt = 0; mn = float('inf')
    for row in states:
        D = np.abs(row[:, None] - row[None, :])
        np.fill_diagonal(D, np.inf)
        vals = D[np.isfinite(D)]
        if vals.size:
            mn = min(mn, float(vals.min()))
            tot += float(vals.sum()); cnt += vals.size
    if not cnt or cl <= 0.0:
        return {'min_norm_dist': float('inf'), 'avg_norm_dist': float('inf'),
                'char_len': cl, 'finite': fin}
    return {'min_norm_dist': mn / cl, 'avg_norm_dist': (tot / cnt) / cl,
            'char_len': cl, 'finite': fin}

def integrate_to_grid(ode):
    a = np.asarray(ode['a'], float); alpha = np.asarray(ode['alpha'], float)
    cc = np.asarray(ode['c'], float); eps = float(ode.get('eps', 0.02))
    y0 = np.asarray(ode['y0'], float)
    t0 = float(ode['t0']); tmax = float(ode['tmax']); M = int(ode['M'])
    tol = float(ode['tol']); budget = int(ode.get('budget', 10 ** 10))
    n = y0.size
    grid = np.linspace(t0, tmax, M)
    spacing = (tmax - t0) / (M - 1) if M > 1 else 0.0
    if n == 0 or M == 1 or tmax == t0:
        return grid, np.tile(y0, (M, 1)), 0
    def run(s):
        h = spacing / s
        out, calls = rk4_full(y0, h, s * (M - 1), a, alpha, cc, eps)
        return out[::s], calls
    S = 1
    prev_states, _ = run(S)
    while True:
        S2 = 2 * S
        cur, calls = run(S2)
        err = float(np.max(np.abs(cur - prev_states))) if cur.shape == prev_states.shape else float('inf')
        if err <= tol * 0.5:
            return grid, cur, calls
        if calls > budget:
            raise RuntimeError('budget exhausted selecting step (would exceed %d calls)' % budget)
        prev_states = cur
        S = S2

def _subsample(case):
    ode = dict(case['ode']); ens = case.get('ensemble', {})
    s = int(case['_s'])
    master = int(ens.get('master_seed', 101))
    noise = float(ens.get('noise', 0.05))
    rng = np.random.default_rng(master * 7919 + s)
    a = np.asarray(ode['a'], float)
    ode['y0'] = (np.sort(a + rng.normal(0.0, noise, a.size))).tolist()
    grid, states, calls = integrate_to_grid(ode)
    pm = physics_metrics(states, a)
    return {'s': s, 'final': [float(x) for x in states[-1]],
            'min_norm_dist': pm['min_norm_dist'], 'avg_norm_dist': pm['avg_norm_dist'],
            'pid': os.getpid(), 'calls': calls}

def run_ensemble(case):
    K = int(case['ensemble']['K']); n_jobs = int(case['ensemble']['n_jobs'])
    def run(mode, nj):
        t0 = time.perf_counter()
        res = []
        if mode == 'serial':
            for s in range(K):
                sub = dict(case); sub['_s'] = s; res.append(_subsample(sub))
        else:
            subs = [dict(case, _s=s) for s in range(K)]
            with ProcessPoolExecutor(max_workers=nj) as ex:
                res = list(ex.map(_subsample, subs))
        return time.perf_counter() - t0, res
    tseq, seq = run('serial', 1)
    tpar, par = run('parallel', n_jobs)
    seqmap = {r['s']: r for r in seq}; parmap = {r['s']: r for r in par}
    maxdiff = 0.0
    for s in seqmap:
        maxdiff = max(maxdiff, float(np.max(np.abs(np.asarray(seqmap[s]['final']) -
                                                     np.asarray(parmap[s]['final'])))))
    def aggr(rs):
        return (float(np.mean([r['min_norm_dist'] for r in rs])),
                float(np.mean([r['avg_norm_dist'] for r in rs])))
    smin, savg = aggr(seq); pmin, pavg = aggr(par)
    return {
        'n_jobs': n_jobs,
        'sequential': {'seconds': tseq, 'pids': sorted(set(r['pid'] for r in seq)),
                       'distinct_pids': len(set(r['pid'] for r in seq)),
                       'min_norm_dist': smin, 'avg_norm_dist': savg},
        'parallel': {'seconds': tpar, 'pids': sorted(set(r['pid'] for r in par)),
                     'distinct_pids': len(set(r['pid'] for r in par)),
                     'min_norm_dist': pmin, 'avg_norm_dist': pavg},
        'max_parallel_serial_abs_diff': maxdiff,
        'speedup': (tseq / tpar) if tpar > 0 else 0.0,
    }

def main():
    cmd, case_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
    case = json.load(open(case_path))
    if cmd == 'trajectory':
        grid, states, calls = integrate_to_grid(case['ode'])
        pm = physics_metrics(states, case['ode']['a'])
        out = {'id': case.get('id'), 'tgrid': [float(x) for x in grid],
               'states': [[float(v) for v in row] for row in states],
               'eval_count': int(calls), 'metrics': pm}
    elif cmd == 'ensemble':
        out = run_ensemble(case)
    else:
        raise SystemExit('unknown command: ' + cmd)
    with open(out_path, 'w') as f:
        json.dump(out, f); f.write('\n')
    print(json.dumps(out, default=str)[:160], flush=True)

if __name__ == '__main__':
    main()
PY

cat > /app/eig.py <<'PY'
#!/usr/bin/env python3
"""Nectar Gasket spectral tools.

dominant_eig(M): the largest-magnitude eigenvalue of a (possibly non-symmetric,
complex-valued) matrix, with an exact deterministic tie-break.
principal_minor_spectra(M): the row of dominant eigenvalues of every leading
principal minor M[:j,:j].
CLI: python3 eig.py <in.json> <out.json>
"""
import sys, json, numpy as np
from scipy.linalg import eigvals

def dominant_eig(M):
    """Return the eigenvalue with largest magnitude; on equal magnitudes prefer
    the one with the larger real part, then the smaller |imag|."""
    M = np.asarray(M, dtype=float)
    w = eigvals(M)
    order = np.lexsort((np.abs(np.imag(w)), -np.real(w), -np.abs(w)))
    return complex(w[order[0]])

def principal_minor_spectra(M, max_k=None):
    M = np.asarray(M, dtype=float)
    n = M.shape[0]
    if max_k is None:
        max_k = n
    max_k = max(1, min(max_k, n))
    return [complex(dominant_eig(M[:j, :j])) for j in range(1, max_k + 1)]

def main():
    inp = json.load(open(sys.argv[1]))
    if 'file' in inp:
        A = np.load(inp['file']).astype(float)
        do_pm = bool(inp.get('do_pm', False))
    else:
        A = np.asarray(inp['matrix'], dtype=float)
        do_pm = bool(inp.get('do_pm', False))
    d = dominant_eig(A)
    out = {'dominant': [d.real, d.imag], 'dominant_mag': abs(d), 'size': int(A.shape[0])}
    if do_pm:
        out['principal_minor_spectra'] = [[z.real, z.imag]
                                          for z in principal_minor_spectra(A)]
    json.dump(out, open(sys.argv[2], 'w'))
    print(json.dumps(out)[:200], flush=True)

if __name__ == '__main__':
    main()
PY

chmod +x /app/integrate.py /app/eig.py

# Run the real deliverables to produce the required report and proof-of-work.
python3 /app/integrate.py trajectory /app/sample_garden.json /app/trajectory.json
python3 /app/integrate.py ensemble  /app/sample_garden.json /app/metrics.json
python3 /app/eig.py /app/visible_eig.json /app/answer_eig.json

echo "metrics.json bytes:  $(wc -c < /app/metrics.json)"
echo "trajectory.json bytes: $(wc -c < /app/trajectory.json)"
echo "answer_eig.json bytes: $(wc -c < /app/answer_eig.json)"

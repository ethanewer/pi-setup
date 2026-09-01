#!/bin/bash
# Verifier for basalt-quill (executes-deliverable).
# Every deliverable is executed (including on hidden inputs), then the reward
# (0 or 1) is written to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
reward=0

if python3 - <<'PY'
import json
import os
import subprocess
import sys

import numpy as np

HD = '/tests/hidden'
probs = []


def check(name, cond, detail=''):
    if not cond:
        probs.append('%s  <%s>' % (name, detail))


# deliverables must all exist
for f in ['/app/fit_spectra.py', '/app/fit_results.json', '/app/stack_models.py',
          '/app/separability.json', '/app/cross_entropy_opt.py', '/app/ars.R',
          '/app/sample.csv']:
    check('deliverable_%s' % os.path.basename(f), os.path.isfile(f), f)

# ---------------------------------------------------------------------------
# 1) Lorentzian spectrum fitting on hidden fixtures
# ---------------------------------------------------------------------------
FIT_TOL = {'center': 0.8, 'width_rel': 0.12, 'amp_rel': 0.12, 'offset': 0.20}
for case in ['single', 'two', 'zero', 'constant', 'empty']:
    spec = os.path.join(HD, case, 'spectrum.csv')
    out = '/tmp/fit_%s.json' % case
    r = subprocess.run(['python3', '/app/fit_spectra.py', spec,
                        '-o', out], capture_output=True, text=True)
    check('fit_%s_exit' % case, r.returncode == 0, r.stderr[-200:])
    if r.returncode != 0:
        continue
    try:
        got = json.load(open(out))['peaks']
        exp = json.load(open(os.path.join(HD, case, 'meta.json')))
    except Exception as exc:  # noqa: BLE001
        check('fit_%s_parse' % case, False, str(exc))
        continue
    check('fit_%s_count' % case, len(got) == len(exp),
          'got %d expected %d' % (len(got), len(exp)))
    if len(got) != len(exp):
        continue
    got = sorted(got, key=lambda d: d['center'])
    exp = sorted(exp, key=lambda d: d['center'])
    for gi in range(len(exp)):
        g, e = got[gi], exp[gi]
        check('fit_%s[%d]center' % (case, gi),
              abs(g['center'] - e['center']) <= FIT_TOL['center'], (g, e))
        check('fit_%s[%d]width' % (case, gi),
              abs(g['width'] / e['width'] - 1) <= FIT_TOL['width_rel'], (g, e))
        check('fit_%s[%d]amp' % (case, gi),
              abs(g['amplitude'] / e['amplitude'] - 1) <= FIT_TOL['amp_rel'], (g, e))
        check('fit_%s[%d]offset' % (case, gi),
              abs(g['offset'] - e['offset']) <= FIT_TOL['offset'], (g, e))

# static fit_results.json reproducible from the shipped default fixture
r = subprocess.run(['python3', '/app/fit_spectra.py',
                    '/app/spectrum.csv', '-o', '/tmp/fit_def.json'],
                   capture_output=True, text=True)
try:
    rep = json.load(open('/tmp/fit_def.json'))
    given = json.load(open('/app/fit_results.json'))
    check('fit_results_repro', rep == given, (given, rep))
except Exception as exc:  # noqa: BLE001
    check('fit_results_repro', False, str(exc))

# ---------------------------------------------------------------------------
# 2) Separability matrix on hidden compound-model specs (vs astropy ground truth)
# ---------------------------------------------------------------------------
from astropy.modeling import models as _ams  # noqa: E402
from astropy.modeling.mappings import Mapping  # noqa: E402
from astropy.modeling.separable import separability_matrix as _asep  # noqa: E402


def _rb(expr):
    op = expr.get('op')
    lk = 'a' if 'a' in expr else 'left'
    rk = 'b' if 'b' in expr else 'right'
    if op == 'cat':
        return _rb(expr[lk]) & _rb(expr[rk])
    if op == 'pipe':
        return _rb(expr[lk]) | _rb(expr[rk])
    leaf = expr['leaf']
    if leaf == 'shift':
        return _ams.Shift(offset=expr['offset'])
    if leaf == 'scale':
        return _ams.Scale(factor=expr['factor'])
    if leaf == 'linear':
        return _ams.Linear1D(slope=expr['slope'], intercept=expr['intercept'])
    if leaf == 'mapping':
        return Mapping(expr['index'], n_inputs=expr['n_in'])
    if leaf == 'poly2d':
        return _ams.Polynomial2D(expr['degree'], **expr['coeffs'])
    if leaf == 'rotation':
        return _ams.Rotation2D(expr['angle'])
    raise ValueError(leaf)


for case in ['stack_a', 'stack_b', 'stack_c']:
    spec_p = os.path.join(HD, case, 'spec.json')
    try:
        expr = json.load(open(spec_p))
        model = _rb(expr)
        expected = _asep(model).astype(int).tolist()
    except Exception as exc:  # noqa: BLE001
        check('stack_%s_ref' % case, False, str(exc))
        continue
    out = '/tmp/o_%s.json' % case
    r = subprocess.run(['python3', '/app/stack_models.py', spec_p,
                        '-o', out], capture_output=True, text=True)
    check('stack_%s_exit' % case, r.returncode == 0, r.stderr[-200:])
    got = {}
    if os.path.isfile(out):
        try:
            got = json.load(open(out))
        except Exception as exc:  # noqa: BLE001
            check('stack_%s_parse' % case, False, str(exc))
    check('stack_%s_nin' % case, got.get('n_inputs') == int(model.n_inputs),
          (got.get('n_inputs'), model.n_inputs))
    check('stack_%s_nout' % case, got.get('n_outputs') == int(model.n_outputs),
          (got.get('n_outputs'), model.n_outputs))
    check('stack_%s_matrix' % case, got.get('matrix') == expected, (got.get('matrix'), expected))

# static separability.json matches astropy ground truth for default shipped spec
try:
    expr = json.load(open('/app/spec_default.json'))
    model = _rb(expr)
    exp_def = _asep(model).astype(int).tolist()
    given = json.load(open('/app/separability.json'))
    check('separability_matrix', given.get('matrix') == exp_def, (given, exp_def))
    check('separability_dims', given.get('n_inputs') == int(model.n_inputs)
          and given.get('n_outputs') == int(model.n_outputs), given)
except Exception as exc:  # noqa: BLE001
    check('separability', False, str(exc))

# ---------------------------------------------------------------------------
# 3) Cross-entropy optimizer + shared-prefix memoization
# ---------------------------------------------------------------------------
opt_path = os.path.join(HD, 'ce_opt', 'spec.json')
opt_spec = json.load(open(opt_path))
r = subprocess.run(['python3', '/app/cross_entropy_opt.py',
                    'optimize', '--spec', opt_path, '-o', '/tmp/opt.json'],
                   capture_output=True, text=True)
check('ce_optimize_exit', r.returncode == 0, r.stderr[-250:])
if r.returncode == 0:
    try:
        o = json.load(open('/tmp/opt.json'))
        theta0 = np.asarray(opt_spec['theta0'])
        theta = np.asarray(o['final_theta'])
        check('ce_shape', tuple(theta.shape) == tuple(theta0.shape), (theta.shape, theta0.shape))
        check('ce_rowsum', bool(np.allclose(theta.sum(axis=1), 1.0, atol=1e-4)),
              theta.sum(axis=1).tolist())
        check('ce_nonneg', float(theta.min()) >= 0.0, float(theta.min()))
        check('ce_finite', bool(np.all(np.isfinite(theta))))
        check('ce_improves', float(o.get('improvement', -9)) > 1.0, o.get('improvement'))
        check('ce_iter', len(o.get('history', [])) == int(opt_spec.get('n_iterations', 14)))
    except Exception as exc:  # noqa: BLE001
        check('ce_optimize_parse', False, str(exc))

mem_path = os.path.join(HD, 'ce_memo', 'spec.json')
mspec = json.load(open(mem_path))
W = np.asarray(mspec['W'], float)
BP = np.asarray(mspec['BP'], float)
XC = np.asarray(mspec['XC'], float)
seqs = mspec['sequences']


def ref_score(aa):
    K = W.shape[1]
    freq = [0] * K
    v = 0.0
    for i, x in enumerate(aa):
        a = int(x)
        freq[a] += 1
        v += float(W[i][a])
        if freq[a] > 1:
            v += float(BP[i][freq[a]])
        v += float(sum(XC[i][j] * freq[j] for j in range(len(freq))))
    return v


r = subprocess.run(['python3', '/app/cross_entropy_opt.py', 'memo',
                    '--spec', mem_path, '-o', '/tmp/memo.json'],
                   capture_output=True, text=True)
check('ce_memo_exit', r.returncode == 0, r.stderr[-250:])
if r.returncode == 0:
    try:
        m = json.load(open('/tmp/memo.json'))
        mine = m.get('scores', [])
        ref = [ref_score(q) for q in seqs]
        check('ce_memo_count', len(mine) == len(seqs), (len(mine), len(seqs)))
        diff = max((abs(float(a) - float(b)) for a, b in zip(mine, ref)), default=0.0)
        check('ce_memo_exact', diff <= 1e-6, diff)
        check('ce_memo_speedup', float(m.get('speedup', 0.0)) > 2.0, m.get('speedup'))
    except Exception as exc:  # noqa: BLE001
        check('ce_memo_parse', False, str(exc))

# ---------------------------------------------------------------------------
# 4) Adaptive rejection sampling (R)
# ---------------------------------------------------------------------------
check('ars_exists', os.path.isfile('/app/ars.R'))

samplep = '/app/sample.csv'
check('sample_exists', os.path.isfile(samplep))
if os.path.isfile(samplep):
    try:
        import csv as _csv  # noqa: E402
        with open(samplep) as fh:
            rows = list(_csv.reader(fh))[1:]
        vals = [float(x[0]) for x in rows if x]
        check('sample_rows', len(vals) >= 1000, len(vals))
        check('sample_finite', all(np.isfinite(v) for v in vals))
    except Exception as exc:  # noqa: BLE001
        check('sample_parse', False, str(exc))

rprobe = (
    'suppressMessages(source("%s"))\n'
    's1 <- ars(function(x) -0.5*x^2, -8, 8, 5000, seed=11)\n'
    'write(c(length(s1), as.numeric(all(is.finite(s1))), mean(s1), sd(s1)), "/tmp/a1")\n'
    'gf <- function(x) 2*log(x) - x\n'
    's2 <- ars(gf, 1e-3, 20, 5000, seed=12)\n'
    'write(c(length(s2), as.numeric(all(is.finite(s2))), mean(s2), sd(s2)), "/tmp/a2")\n'
) % '/app/ars.R'
with open('/tmp/probe.R', 'w') as fh:
    fh.write(rprobe)
rrr = subprocess.run(['Rscript', '--vanilla', '/tmp/probe.R'],
                     capture_output=True, text=True)
check('ars_rscript_ok', os.path.isfile('/tmp/a1') and os.path.isfile('/tmp/a2'),
      rrr.stderr[-200:])
def _read2(p):
    with open(p) as fh:
        return [float(x) for x in fh.read().split()]
if os.path.isfile('/tmp/a1'):
    l1 = _read2('/tmp/a1')
    check('ars1_count', l1[0] == 5000, l1[:1])
    check('ars1_finite', l1[1] == 1.0, l1)
    check('ars1_mean', abs(l1[2]) <= 0.08, l1)
    check('ars1_sd', abs(l1[3] - 1.0) <= 0.10, l1)
if os.path.isfile('/tmp/a2'):
    l2 = _read2('/tmp/a2')
    check('ars2_count', l2[0] == 5000, l2[:1])
    check('ars2_finite', l2[1] == 1.0, l2)
    check('ars2_mean', abs(l2[2] - 3.0) <= 0.05, l2)
    check('ars2_sd', abs(l2[3] - np.sqrt(3.0)) <= 0.15, l2)

if probs:
    for p in probs:
        print('FAIL:', p)
    sys.exit(1)
print('ALL_VERIFIER_GATES_OK')
PY
then
  reward=1
fi

echo "$reward" > /logs/verifier/reward.txt
exit 0
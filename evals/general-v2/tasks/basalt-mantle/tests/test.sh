#!/bin/bash
# Verifier for basalt-mantle (executes-deliverable).
#
# Executes BOTH deliverables then independently replays each originally-failing
# check. Reward is 1 only when every capability + every hidden edge case passes.
set -u
mkdir -p /logs/verifier
reward=0

if python3 - <<'PY'
import json
import os
import subprocess
import sys

HD = '/tests/hidden'
probs = []


def check(name, cond, detail=''):
    if not cond:
        probs.append('%s  <%s>' % (name, detail))


def closeness(a, b, tol=1e-9):
    try:
        return isinstance(a, (int, float)) and isinstance(b, (int, float)) \
            and abs(float(a) - float(b)) < tol
    except Exception:  # noqa: BLE001
        return False


# ---- execute deliverable /app/repair.sh (idempotent) ----
r = subprocess.run(['bash', '/app/repair.sh'], capture_output=True, text=True)
check('repair_sh_exit0', r.returncode == 0, r.stderr[-300:])

# ---- execute deliverable /app/verify.py ----
vp = subprocess.run(['python3', '/app/verify.py'], capture_output=True, text=True)
check('verify_py_all_ok', vp.returncode == 0 and 'ALL_OK' in vp.stdout,
      vp.stdout[-300:])


# ---- 1) default-interpreter package kether ----
try:
    import kether
    check('kether_flow_visible', closeness(kether.flows([1.0, 2.0, 3.0]), 6.0))
    check('kether_mean_visible', closeness(kether.algebraic_mean([1, 2, 3]), 2.0))
except Exception as exc:
    check('kether_import', False, str(exc))

k_h = json.load(open(os.path.join(HD, 'kether_edges.json')))
for i, x in enumerate(k_h['inputs']):
    try:
        got = kether.flows(x)
    except Exception as exc:
        got = exc
    check('kether_hidden_%d' % i, closeness(got, k_h['expected'][i]), (x, got))

# ---- 2) edited package spect reinstall + target suite ----
pt = subprocess.run(['python3', '-m', 'pytest', '-q', '/app/shelf/spect/tests'],
                    capture_output=True, text=True)
out = pt.stdout + pt.stderr
check('spect_pytest_green', pt.returncode == 0 and 'passed' in out
      and 'failed' not in out, out[-300:])
s_h = json.load(open(os.path.join(HD, 'spect_edges.json')))
import spect
for i, x in enumerate(s_h['inputs']):
    try:
        got = spect.prefix_digest(x)
    except Exception as exc:
        got = exc
    check('spect_hidden_%d' % i, got == s_h['expected'][i], (x, got))

# ---- 3) cython/numpy 2.x extension pyros ----
try:
    import numpy
    import pyros
    check('pyros_numpy2', numpy.__version__.startswith('2.'))
    check('pyros_visible', closeness(pyros.ring(5), 55.0))
    check('pyros_converge_visible', closeness(pyros.converge([2.0, 2.0]), 4.0))
except Exception as exc:
    check('pyros_import', False, str(exc))
p_h = json.load(open(os.path.join(HD, 'pyros_edges.json')))
for i, x in enumerate(p_h['converge']['inputs']):
    try:
        got = pyros.converge(x)
    except Exception as exc:
        got = exc
    check('pyros_converge_hidden_%d' % i, closeness(got, p_h['converge']['expected'][i]), (x, got))
for i, x in enumerate(p_h['ring']['inputs']):
    try:
        got = pyros.ring(x)
    except Exception as exc:
        got = exc
    check('pyros_ring_hidden_%d' % i, closeness(got, p_h['ring']['expected'][i]), (x, got))

# ---- 4) OSMesa loader (incl. malformed-interface hidden scenario) ----
g = subprocess.run(['python3', '/app/gloss/fern_gl.py'],
                   capture_output=True, text=True)
check('fern_gl_normal', g.returncode == 0 and 'OSMESA_OK' in g.stdout,
      g.stdout + g.stderr)
bogus = dict(os.environ)
bogus['FERN_GL_LIB'] = '/nonexistent/orp/: ./also/bogus'
g2 = subprocess.run(['python3', '/app/gloss/fern_gl.py'],
                    capture_output=True, text=True, env=bogus)
check('fern_gl_bogus_env_fallback', g2.returncode == 0 and 'OSMESA_OK' in g2.stdout,
      g2.stdout + g2.stderr)

# ---- 5) interpreter shim in settings + profiler runner ----
with open('/app/ima/runner/settings.json') as f:
    cfg = json.load(f)
shim = (cfg.get('python_shim') or '').strip()
check('python_shim_nonempty', bool(shim), repr(shim))
check('python_shim_real', bool(shim) and os.path.isfile(shim)
      and os.access(shim, os.X_OK), shim)
sp = subprocess.run(['python3', '/app/ima/runner/spire.py',
                     '/app/ima/runner/target_probe.py'],
                    capture_output=True, text=True)
check('spire_cprofile_run', sp.returncode == 0 and 'SPIRE_OK' in sp.stdout,
      sp.returncode)

# ---- 6) R statistical runtime self-test ----
rsc = (cfg.get('rscript') or '').strip()
check('rscript_nonempty', bool(rsc), repr(rsc))
check('rscript_real', bool(rsc) and os.path.isfile(rsc) and os.access(rsc, os.X_OK), rsc)
rsu = subprocess.run(['python3', '/app/ima/runner/rself.py'],
                     capture_output=True, text=True)
check('r_self_test', rsu.returncode == 0 and 'R_SELFTEST' in rsu.stdout,
      rsu.stdout + rsu.stderr)

# ---- 7) R Jupyter kernel + R analysis package ----
ks = '/root/.local/share/jupyter/kernels/rcausal/kernel.json'
argv0 = ''
if os.path.isfile(ks):
    try:
        kd = json.load(open(ks))
        argv0 = (kd.get('argv') or [''])[0]
    except Exception:  # noqa: BLE001
        argv0 = ''
check('rcausal_kernel_json', os.path.isfile(ks))
check('rcausal_kernel_argv', bool(argv0) and os.path.isfile(argv0)
      and os.access(argv0, os.X_OK), argv0)
kl = subprocess.run(['jupyter', 'kernelspec', 'list'],
                    capture_output=True, text=True)
check('rcausal_kernel_listed', 'rcausal' in kl.stdout, kl.stdout)
ja = subprocess.run(['Rscript', '--vanilla', '-e',
                     'suppressMessages(library(jsonlite)); cat("JL_READY")'],
                    capture_output=True, text=True)
check('r_analysis_pkg', ja.returncode == 0 and 'JL_READY' in ja.stdout,
      ja.stdout + ja.stderr)

if probs:
    for p in probs:
        print('FAIL:', p)
    sys.exit(1)
print('ALL_VERIFIER_GATES_OK')
PY
then reward=1
fi

echo "$reward" > /logs/verifier/reward.txt
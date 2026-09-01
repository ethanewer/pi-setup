#!/usr/bin/env python3
"""Driver: build the C extension, check against the NumPy reference, benchmark,
and write the deliverables /app/result.json, /app/benchmark.json, /app/weights.json.
"""
import json, os, shutil, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = '/app/work'
os.makedirs(WORK, exist_ok=True)

# 1. stage build sources
for fn in ('setup.py', 'fast_port.c'):
    shutil.copy(os.path.join(HERE, fn), os.path.join(WORK, fn))

# 2. compile the extension in place (+ ensure importable from /app)
os.chdir(WORK)
sys.argv = ['setup.py', 'build_ext', '--inplace']
exec(compile(open('setup.py').read(), 'setup.py', 'exec'), {'__name__': '__main__'})
sys.path.insert(0, WORK)
sys.path.insert(0, '/app')

import numpy as np
import fastport

# 3. reference statistics from prices.csv
raw = np.genfromtxt('/app/prices.csv', delimiter=',', names=True)
cols = [raw[c] for c in raw.dtype.names]
P = np.column_stack(cols)
R = P[1:] / P[:-1] - 1.0
mu = R.mean(axis=0)
cov = np.cov(R, rowvar=False)
n = P.shape[1]
w = np.full(n, 1.0 / n)

ret_ref = float(w @ mu)
var_ref = float(w @ (cov @ w))

ret_native, var_native = fastport.compute(w, mu, cov)

# 4. benchmark
calls = 3000
t0 = time.perf_counter()
for _ in range(calls):
    fastport.compute(w, mu, cov)
t_native = (time.perf_counter() - t0) / calls

t0 = time.perf_counter()
for _ in range(calls):
    float(w @ mu); float(w @ (cov @ w))
t_numpy = (time.perf_counter() - t0) / calls

json.dump({
    'expected_return': ret_native,
    'portfolio_variance': var_native,
    'n_assets': int(n),
}, open('/app/result.json', 'w'), indent=2)

json.dump({
    'c_seconds_per_call': t_native,
    'numpy_seconds_per_call': t_numpy,
    'speedup': (t_numpy / t_native) if t_native > 0 else 0.0,
    'calls': calls,
}, open('/app/benchmark.json', 'w'), indent=2)

json.dump([float(x) for x in w], open('/app/weights.json', 'w'))

assert abs(ret_native - ret_ref) < 1e-9 and abs(var_native - var_ref) < 1e-9
print('OK ret=%.9g var=%.3g' % (ret_native, var_native))
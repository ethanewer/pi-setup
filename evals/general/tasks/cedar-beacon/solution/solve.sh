#!/usr/bin/env bash
# Oracle for cedar-beacon: writes the real /app/solve.py that implements the whole
# pipeline (handwritten RK4, Fortran regenerator, MATLAB port, softmax risk), then
# runs it with no arguments to produce /app/answer.json. Never reads /tests.
set -eu

cat > /app/solve.py <<'PY'
#!/usr/bin/env python3
"""Cedar Beacon slope-risk numeric pipeline.

Handwritten fixed-step RK4 for a 3-species linear decay cascade; compiles+reruns a
shipped Fortran regenerator; ports a MATLAB forward-attenuation routine; computes a
numerically stable softmax attention risk estimator.
"""
import sys, os, json, math, subprocess

# ----------------------------------------------------------------------------
# Part A - handwritten fixed-step 4th-order Runge-Kutta for the cascade
# ----------------------------------------------------------------------------
def rk4_cascade(lam, init, tmax, steps):
    lam = [float(x) for x in lam]
    y = [float(v) for v in init]
    steps = int(steps)
    h = (float(tmax) / steps) if steps > 0 else 0.0

    def deriv(yv):
        A, B, C = yv
        kA, kB, kC = lam
        return [-kA * A, kA * A - kB * B, kB * B - kC * C]

    peak = sum(y)
    for _ in range(steps):
        k1 = deriv(y)
        kmid1 = [y[i] + 0.5 * h * k1[i] for i in range(3)]
        k2 = deriv(kmid1)
        kmid2 = [y[i] + 0.5 * h * k2[i] for i in range(3)]
        k3 = deriv(kmid2)
        kend = [y[i] + h * k3[i] for i in range(3)]
        k4 = deriv(kend)
        y = [y[i] + (h / 6.0) * (k1[i] + 2 * k2[i] + 2 * k3[i] + k4[i])
             for i in range(3)]
        tot = sum(y)
        if tot > peak:
            peak = tot
    return sum(y), peak

# ----------------------------------------------------------------------------
# Part B - compile and run the Fortran regenerator -> /app/derived/flag.txt
# ----------------------------------------------------------------------------
def regenerate():
    os.makedirs('/app/derived', exist_ok=True)
    subprocess.run(['gfortran', '-O2', '/app/src/regen.f90',
                    '-o', '/app/derived/regen_bin'], check=True)
    subprocess.run(['/app/derived/regen_bin', '/app/derived/flag.txt'], check=True)
    with open('/app/derived/flag.txt') as fh:
        content = fh.read()
    if len(content.strip()) == 0:
        raise RuntimeError('regenerator produced empty output')
    return 'flag.txt present and non-empty'

# ----------------------------------------------------------------------------
# Part C - MATLAB gamma.m port (elementwise paths, reversed flip, odd ramp,
#          endpoint concat)
# ----------------------------------------------------------------------------
def gamma_path(fin, leak):
    fin = [float(x) for x in fin]
    leak = float(leak)
    n = len(fin)
    a = [(x + leak) * 1.5 for x in fin]      # control path: leak-boosted
    b = fin[::-1]                            # reflected path: reversed order
    ramp = [0.0] * n
    for i in range(0, n, 2):                 # 1-indexed odd -> 0-based even
        ramp[i] = fin[i]
    g = [a[i] + b[i] + ramp[i] for i in range(n)]
    scalar = sum(g) + g[0] + g[-1]           # endpoint concat derived scalar
    return g, scalar

# ----------------------------------------------------------------------------
# Part D - risk estimator: numerically stable softmax attention
# ----------------------------------------------------------------------------
def risk_attention(values, weights):
    values = [float(x) for x in values]
    n = len(values)
    if n == 0:
        return [], 0.0, 0.0
    if len(weights) != n:
        weights = [1.0] * n
    weights = [float(x) for x in weights]
    mx = max(values)
    ex = [math.exp(v - mx) for v in values]
    tot = sum(ex)
    attn = [e / tot for e in ex]
    attn_sum = sum(attn)
    score = sum(attn[i] * weights[i] for i in range(n))
    return attn, attn_sum, score

# ----------------------------------------------------------------------------
# pipeline driver
# ----------------------------------------------------------------------------
def run_case(case):
    lam = case['ode']['lam']
    init = case['ode']['init']
    tmax = case['ode']['tmax']
    steps = case['ode']['steps']
    final_total, peak_total = rk4_cascade(lam, init, tmax, steps)

    g, g_scalar = gamma_path(case['gamma']['fin'], case['gamma']['leak'])

    attn, attn_sum, score = risk_attention(
        case['risk'].get('values', []), case['risk'].get('weights', []))

    regen = regenerate()

    return {
        'id': case.get('id', 'unnamed'),
        'ode': {'final_total': final_total, 'peak_total': peak_total},
        'gamma': {'array': g, 'scalar': g_scalar},
        'risk': {'attn': attn, 'attn_sum': attn_sum, 'score': score},
        'regen': regen,
    }

SAMPLE = {
    'id': 'visible-sample',
    'ode': {'lam': [0.03, 0.12, 0.005], 'init': [120.0, 40.0, 0.0],
            'tmax': 150.0, 'steps': 1500},
    'gamma': {'fin': [1.2, 0.8, 2.1, 0.4], 'leak': 0.25},
    'risk': {'values': [2.0, 1.0, 3.5, 0.5], 'weights': [0.2, 0.3, 0.4, 0.1]},
}

def main():
    if len(sys.argv) >= 3:
        case_path, out_path = sys.argv[1], sys.argv[2]
        case = json.load(open(case_path))
    elif len(sys.argv) == 2:
        case_path, out_path = sys.argv[1], '/app/answer.json'
        case = json.load(open(case_path))
    else:
        case, out_path = SAMPLE, '/app/answer.json'
    result = run_case(case)
    with open(out_path, 'w') as fh:
        json.dump(result, fh, indent=2)
        fh.write('\n')

if __name__ == '__main__':
    main()
PY

chmod +x /app/solve.py

# Prove the pipeline works end to end and produce /app/answer.json.
python3 /app/solve.py
echo "answer.json written: $(wc -c < /app/answer.json) bytes"
echo "flag.txt lines: $(wc -l < /app/derived/flag.txt)"

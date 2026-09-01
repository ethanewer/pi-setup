#!/bin/bash
# zephyr-forge oracle: writes six CLIs and runs them on the visible case.
set -eu

cat > /app/lib.py <<'PYEOF'
#!/usr/bin/env python3
"""zephyr-forge solver engine (oracle + reference contract for agents)."""
import sys, os, json, glob
import numpy as np
from fractions import Fraction

# ---------------------------------------------------------------- MIP
def solve_mip(in_mps, out_txt):
    import highspy
    h = highspy.Highs()
    h.setOptionValue('output_flag', False)
    h.readModel(in_mps)
    h.run()
    obj = float(h.getObjectiveValue())
    with open(out_txt, 'w') as f:
        f.write("OBJECTIVE %.10g\n" % obj)

# ---------------------------------------------------------------- MAX-SAT
def parse_maxsat(path):
    toks = [ln.split('#')[0].strip() for ln in open(path) if not ln.lstrip().startswith('#')]
    toks = [t for t in toks if t]
    n = None; hard = []; soft = []; sec = None
    for t in toks:
        if t.startswith('VAR'):
            n = int(t.split()[1]); continue
        if t == 'HARD':
            sec = 'hard'; continue
        if t == 'SOFT':
            sec = 'soft'; continue
        parts = [int(x) for x in t.split()]
        if sec == 'hard':
            hard.append(parts)
        else:
            soft.append((parts[0], parts[1:]))
    return n, hard, soft

def clause_sat(cl, mask):
    for lit in cl:
        v = abs(lit) - 1
        val = bool(mask & (1 << v))
        if (lit > 0 and val) or (lit < 0 and not val):
            return True
    return False

def solve_maxsat(in_txt, out_json):
    n, hard, soft = parse_maxsat(in_txt)
    best = -1
    for mask in range(1 << n):
        ok = True
        for cl in hard:
            if not clause_sat(cl, mask):
                ok = False
                break
        if not ok:
            continue
        w = 0
        for wgt, cl in soft:
            if clause_sat(cl, mask):
                w += wgt
        if w > best:
            best = w
    if best < 0:
        d = {"status": "HARD_UNSAT"}
    else:
        d = {"status": "OPTIMAL", "objective": int(best)}
    with open(out_json, 'w') as f:
        json.dump(d, f)

# ---------------------------------------------------------------- Quartic
def parse_quartic(path):
    lines = [ln.split('#')[0].strip() for ln in open(path)]
    lines = [ln for ln in lines if ln]
    P = {}
    inA = False
    A = []
    for ln in lines:
        toks = ln.split()
        key = toks[0]
        if key == 'n':
            P['n'] = int(toks[1])
        elif key in ('a', 't', 'c'):
            P.setdefault(key, [float(x) for x in toks[1:]])
        elif key == 'penalty':
            P['penalty'] = float(toks[1])
        elif key == 'coupling':
            P['coupling'] = float(toks[1])
        elif key == 'start':
            P['start'] = [float(x) for x in toks[1:]]
        elif key == 'A':
            inA = True
            if len(toks) > 1:
                A.append([float(x) for x in toks[1:]])
        elif inA and key and (key[0].isdigit() or key[0] in '+-'):
            A.append([float(x) for x in toks])
    P['A'] = A
    return P

def quartic_obj(P, x):
    x = np.asarray(x, dtype=float)
    a = np.asarray(P['a']); t = np.asarray(P['t']); c = np.asarray(P['c'])
    A = np.asarray(P['A']); pen = P['penalty']; coup = P['coupling']
    f = np.sum(a * (x - t) ** 4) + pen * np.sum((x - c) ** 2) + coup * 0.5 * x @ A @ x
    return float(f)

def quartic_grad(P, x):
    x = np.asarray(x, dtype=float)
    a = np.asarray(P['a']); t = np.asarray(P['t']); c = np.asarray(P['c'])
    A = np.asarray(P['A']); pen = P['penalty']; coup = P['coupling']
    g = 4 * a * (x - t) ** 3 + 2 * pen * (x - c) + coup * (A @ x)
    return g

def solve_quartic(in_f, out_json):
    import scipy.optimize as spo
    P = parse_quartic(in_f)
    start = np.asarray(P['start'], dtype=float)
    res = spo.minimize(lambda x: quartic_obj(P, x), start,
                       jac=lambda x: quartic_grad(P, x), method='L-BFGS-B',
                       options={"maxiter": 6000, "ftol": 1e-14, "gtol": 1e-10})
    x = res.x
    obj = quartic_obj(P, x)
    grad = float(np.linalg.norm(quartic_grad(P, x)))
    with open(out_json, 'w') as f:
        json.dump({"objective": obj, "gradient_norm": grad,
                   "x": [float(v) for v in x], "success": bool(res.success)}, f)

# ---------------------------------------------------------------- Corners
def parse_corners(path):
    nums = []
    for ln in open(path):
        ln = ln.split('#')[0].strip()
        if ln:
            nums.extend(int(x) for x in ln.split())
    insts = []
    pos = 0
    while pos < len(nums):
        m = nums[pos]; n = nums[pos + 1]; pos += 2
        A = []
        for r in range(m):
            A.append(nums[pos:pos + n]); pos += n
        b = nums[pos:pos + m]; pos += m
        insts.append((m, n, A, b))
    return insts

def det_num(M):
    n = len(M)
    Mm = [row[:] for row in M]
    d = Fraction(1)
    for col in range(n):
        piv = None
        for r in range(col, n):
            if Mm[r][col] != 0:
                piv = r; break
        if piv is None:
            return Fraction(0)
        if piv != col:
            Mm[col], Mm[piv] = Mm[piv], Mm[col]
            d = -d
        pv = Mm[col][col]
        d *= pv
        for r in range(col + 1, n):
            fac = Mm[r][col] / pv
            if fac != 0:
                for k in range(col, n):
                    Mm[r][k] -= fac * Mm[col][k]
    return d

def solve_num(M, b):
    n = len(M)
    A = [row[:] + [bv] for row, bv in zip(M, b)]
    for col in range(n):
        piv = None
        for r in range(col, n):
            if A[r][col] != 0:
                piv = r; break
        if piv is None:
            raise ZeroDivisionError
        A[col], A[piv] = A[piv], A[col]
        pv = A[col][col]
        for k in range(col, n + 1):
            A[col][k] /= pv
        for r in range(n):
            if r != col and A[r][col] != 0:
                fac = A[r][col]
                for k in range(col, n + 1):
                    A[r][k] -= fac * A[col][k]
    return [A[r][n] for r in range(n)]

def count_corners(m, n, A, b):
    import itertools
    A = [[Fraction(x) for x in row] for row in A]
    b = [Fraction(x) for x in b]
    cols = list(itertools.combinations(range(n), m))
    seen = set()
    for T in cols:
        M = [[A[r][c] for c in T] for r in range(m)]
        if det_num(M) == 0:
            continue
        try:
            xs = solve_num(M, b)
        except ZeroDivisionError:
            continue
        ok = all(v >= 0 for v in xs)
        if not ok:
            continue
        full = [Fraction(0)] * n
        for idx, c in enumerate(T):
            full[c] = xs[idx]
        seen.add(tuple(full))
    return len(seen)

def solve_corners(in_txt, out_txt):
    insts = parse_corners(in_txt)
    lines = [str(count_corners(m, n, A, b)) for (m, n, A, b) in insts]
    with open(out_txt, 'w') as f:
        f.write("\n".join(lines) + "\n")

# ---------------------------------------------------------------- Verdicts
def classify(text):
    low = text.lower()
    for mk in ("unsat", "no solution", "could not be solved"):
        if mk in low:
            return "UNSAT"
    return "SAT"

def solve_verdicts(in_dir, out_txt):
    files = sorted(glob.glob(os.path.join(in_dir, "*.txt")))
    lines = []
    for f in files:
        data = open(f, 'rb').read().decode('utf-8', 'replace')
        lines.append(classify(data))
    with open(out_txt, 'w') as f:
        f.write("\n".join(lines) + "\n")

# ---------------------------------------------------------------- Compress
def _has_match_at(data, i, n, thresh):
    maxd = min(255, i)
    for di in range(1, maxd + 1):
        base = i - di
        L = 0
        while L < 255 and i + L < n and data[base + L] == data[i + L]:
            L += 1
        if L >= thresh:
            return True
    return False

def greedy_encode(data):
    n = len(data)
    i = 0
    instrs = []
    while i < n:
        bestL = 0
        bestD = 0
        maxd = min(255, i)
        for di in range(1, maxd + 1):
            base = i - di
            L = 0
            while L < 255 and i + L < n and data[base + L] == data[i + L]:
                L += 1
            if L > bestL:
                bestL, bestD = L, di
            if L == 255:
                break
        if bestL >= 3:
            instrs.append(('B', bestD, bestL))
            i += bestL
        else:
            L = 1
            while L < 255 and i + L < n and not _has_match_at(data, i + L, n, 3):
                L += 1
            instrs.append(('L', data[i:i + L]))
            i += L
    return instrs

def pack_instructions(instrs):
    out = bytearray()
    for it in instrs:
        if it[0] == 'L':
            seg = it[1]
            out += b'L'
            out += len(seg).to_bytes(2, 'little')
            out += seg
        else:
            out += b'B'
            out.append(it[1])
            out.append(it[2])
    return bytes(out)

def decode(bin_data):
    pos = 0
    out = bytearray()
    while pos < len(bin_data):
        t = bin_data[pos]
        pos += 1
        if t == ord('L'):
            L = int.from_bytes(bin_data[pos:pos + 2], 'little')
            pos += 2
            out += bin_data[pos:pos + L]
            pos += L
        elif t == ord('B'):
            d = bin_data[pos]
            l = bin_data[pos + 1]
            pos += 2
            base = len(out) - d
            for k in range(l):
                out.append(out[base + k])
        else:
            raise ValueError("bad tag %d" % t)
    return bytes(out)

def encode_size(data):
    instrs = greedy_encode(data)
    return pack_instructions(instrs)

def solve_compress(in_txt, in_ceiling, out_bin):
    data = open(in_txt, 'rb').read()
    ceil = int(open(in_ceiling).read().strip())
    packed = encode_size(data)
    assert decode(packed) == data
    assert len(packed) < ceil
    with open(out_bin, 'wb') as f:
        f.write(packed)

# ---------------------------------------------------------------- CLI dispatch
def main():
    op = sys.argv[1]
    arg = sys.argv[2:]
    if op == 'mip':
        solve_mip(arg[0], arg[1])
    elif op == 'maxsat':
        solve_maxsat(arg[0], arg[1])
    elif op == 'quartic':
        solve_quartic(arg[0], arg[1])
    elif op == 'corners':
        solve_corners(arg[0], arg[1])
    elif op == 'verdicts':
        solve_verdicts(arg[0], arg[1])
    elif op == 'compress':
        solve_compress(arg[0], arg[1], arg[2])

if __name__ == '__main__':
    main()
PYEOF
chmod 644 /app/lib.py
cat > /app/opt.py <<PYEOF2
import sys
from lib import solve_mip
solve_mip(sys.argv[1], sys.argv[2])
PYEOF2
chmod 644 /app/opt.py
cat > /app/maxsat.py <<PYEOF2
import sys
from lib import solve_maxsat
solve_maxsat(sys.argv[1], sys.argv[2])
PYEOF2
chmod 644 /app/maxsat.py
cat > /app/quartic.py <<PYEOF2
import sys
from lib import solve_quartic
solve_quartic(sys.argv[1], sys.argv[2])
PYEOF2
chmod 644 /app/quartic.py
cat > /app/corners.py <<PYEOF2
import sys
from lib import solve_corners
solve_corners(sys.argv[1], sys.argv[2])
PYEOF2
chmod 644 /app/corners.py
cat > /app/verdicts.py <<PYEOF2
import sys
from lib import solve_verdicts
solve_verdicts(sys.argv[1], sys.argv[2])
PYEOF2
chmod 644 /app/verdicts.py
cat > /app/compress.py <<PYEOF2
import sys
from lib import solve_compress
solve_compress(sys.argv[1], sys.argv[2], sys.argv[3])
PYEOF2
chmod 644 /app/compress.py

echo "running visible case"
python3 /app/opt.py /app/case/model.mps /app/model.mps.optimized.txt
python3 /app/maxsat.py /app/case/maxsat.txt /app/maxsat_solution.json
python3 /app/quartic.py /app/case/quartic.txt /app/quartic_solution.json
python3 /app/corners.py /app/case/corners.txt /app/corners.txt
python3 /app/verdicts.py /app/case/verdicts /app/sat_verdicts.txt
python3 /app/compress.py /app/case/text.txt /app/case/ceiling.txt /app/encode.bin
echo "solve.sh done"

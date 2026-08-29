#!/bin/bash
# zephyr-forge verifier (executes-deliverable).
# Runs each of the six /app CLIs on the visible case and on every /tests/hidden
# case, and independently recomputes the expected result for each of the six
# sub-problems. Writes a 0/1 reward.
set -u
mkdir -p /logs/verifier

python3 - <<'PY'
import sys, os, json, glob, subprocess

HID = "/tests/hidden"
FAIL = []

def fail(msg):
    FAIL.append(msg)

def run_cli(prefix, args, timeout=280):
    r = subprocess.run([sys.executable] + args, capture_output=True, text=True, timeout=timeout)
    if r.returncode != 0:
        fail(prefix + ": CLI error: " + (r.stderr.strip()[:160] or "rc=%d" % r.returncode))
        return False
    return True

# ---------------- independent reference helpers ----------------
def ref_mip(mps):
    import highspy
    h = highspy.Highs(); h.setOptionValue('output_flag', False)
    h.readModel(mps); h.run()
    return float(h.getObjectiveValue())

def parse_maxsat(path):
    toks = [ln.split('#')[0].strip() for ln in open(path) if not ln.lstrip().startswith('#')]
    toks = [t for t in toks if t]
    n = None; hard = []; soft = []
    for t in toks:
        if t.startswith('VAR'):
            n = int(t.split()[1]); continue
        if t == 'HARD': sec = 'hard'; continue
        if t == 'SOFT': sec = 'soft'; continue
        parts = [int(x) for x in t.split()]
        (hard if sec == 'hard' else soft.append) if False else None
        if sec == 'hard':
            hard.append(parts)
        else:
            soft.append((parts[0], parts[1:]))
    return n, hard, soft

def clause_sat(cl, mask):
    for lit in cl:
        v = abs(lit)-1
        if (lit > 0 and (mask>>v)&1) or (lit < 0 and not ((mask>>v)&1)):
            return True
    return False

def ref_maxsat(path):
    n, hard, soft = parse_maxsat(path)
    best = -1
    for mask in range(1 << n):
        ok = all(clause_sat(c, mask) for c in hard)
        if not ok:
            continue
        w = sum(wgt for wgt, c in soft if clause_sat(c, mask))
        if w > best:
            best = w
    return "HARD_UNSAT" if best < 0 else best

# quartic
def parse_quartic(path):
    lines = [ln.split('#')[0].strip() for ln in open(path)]
    lines = [ln for ln in lines if ln]
    P = {}; A = []; inA = False
    for ln in lines:
        toks = ln.split(); k = toks[0]
        if k == 'n': P['n'] = int(toks[1])
        elif k in ('a','t','c'): P.setdefault(k, [float(x) for x in toks[1:]])
        elif k == 'penalty': P['penalty'] = float(toks[1])
        elif k == 'coupling': P['coupling'] = float(toks[1])
        elif k == 'start': P['start'] = [float(x) for x in toks[1:]]
        elif k == 'A':
            inA = True
            if len(toks) > 1: A.append([float(x) for x in toks[1:]])
        elif inA and k and (k[0].isdigit() or k[0] in '+-'):
            A.append([float(x) for x in toks])
    P['A'] = A
    return P

import numpy as np
def q_obj(P, x):
    x = np.asarray(x, float); a=np.asarray(P['a']); t=np.asarray(P['t']); c=np.asarray(P['c'])
    A=np.asarray(P['A']); return float(np.sum(a*(x-t)**4)+P['penalty']*np.sum((x-c)**2)+P['coupling']*0.5*x@A@x)
def q_grad(P, x):
    x = np.asarray(x, float); a=np.asarray(P['a']); t=np.asarray(P['t']); c=np.asarray(P['c']); A=np.asarray(P['A'])
    return 4*a*(x-t)**3 + 2*P['penalty']*(x-c) + P['coupling']*(A@x)

def ref_quartic(path):
    import scipy.optimize as spo
    P = parse_quartic(path)
    st = np.asarray(P['start'], float)
    res = spo.minimize(lambda x:q_obj(P,x), st, jac=lambda x:q_grad(P,x), method='L-BFGS-B',
                       options={"maxiter":6000,"ftol":1e-14,"gtol":1e-10})
    return q_obj(P, res.x)

# corners
def parse_corners_nums(path):
    nums=[]
    for ln in open(path):
        ln = ln.split('#')[0].strip()
        for p in ln.split():
            if p: nums.append(int(p))
    return nums

def nbr_disjoint(nums):
    insts=[]; pos=0
    while pos < len(nums):
        m=nums[pos]; n=nums[pos+1]; pos+=2
        A=[]
        for r in range(m):
            A.append(nums[pos:pos+n]); pos+=n
        b=nums[pos:pos+m]; pos+=m
        insts.append((m,n,A,b))
    return insts

from fractions import Fraction
def count_corners(m,n,A,b):
    import itertools
    Af=[[Fraction(x) for x in row] for row in A]
    bf=[Fraction(x) for x in b]
    seen=set()
    for T in itertools.combinations(range(n), m):
        M=[[Af[r][c] for c in T] for r in range(m)]
        try:
            xs=ru_invert(M,bf)
        except Exception:
            continue
        if all(v>=0 for v in xs):
            full=[Fraction(0)]*n
            for idx,c in enumerate(T): full[c]=xs[idx]
            seen.add(tuple(full))
    return len(seen)

def ru_invert(M,b):
    n=len(M)
    A=[row[:]+[bv] for row,bv in zip(M,b)]
    for col in range(n):
        piv=None
        for r in range(col,n):
            if A[r][col]!=0: piv=r; break
        if piv is None: raise ZeroDivisionError
        A[col],A[piv]=A[piv],A[col]
        pv=A[col][col]
        for k in range(col,n+1): A[col][k]/=pv
        for r in range(n):
            if r!=col and A[r][col]!=0:
                f=A[r][col]
                for k in range(col,n+1): A[r][k]-=f*A[col][k]
    return [A[r][n] for r in range(n)]

def ref_corners(path):
    insts = nbr_disjoint(parse_corners_nums(path))
    return [str(count_corners(m, n, A, b)) for (m, n, A, b) in insts]

# verdicts
def classify(t):
    low=t.lower()
    for mk in ("unsat","no solution","could not be solved"):
        if mk in low: return "UNSAT"
    return "SAT"

def ref_verdicts(d):
    out=[]
    for f in sorted(glob.glob(os.path.join(d,"*.txt"))):
        out.append(classify(open(f,'rb').read().decode('utf-8','replace')))
    return out

# compress decode (fixed format)
def decode(binb):
    pos=0; out=bytearray()
    while pos < len(binb):
        t=binb[pos]; pos+=1
        if t==ord('L'):
            L=int.from_bytes(binb[pos:pos+2],'little'); pos+=2
            out+=binb[pos:pos+L]; pos+=L
        elif t==ord('B'):
            d=binb[pos]; l=binb[pos+1]; pos+=2
            base=len(out)-d
            for k in range(l): out.append(out[base+k])
        else:
            raise ValueError
    return bytes(out)

# ---------------- check one case with the six CLIs ----------------
def check_case(name, casedir, outdir):
    os.makedirs(outdir, exist_ok=True)
    # MIP
    if not run_cli(name, ["/app/opt.py", casedir+"/model.mps", outdir+"/mip.txt"]):
        return
    ref = ref_mip(casedir+"/model.mps")
    try:
        val = float(open(outdir+"/mip.txt").read().split("OBJECTIVE")[1].strip())
    except Exception:
        fail(name+": mip output not parseable"); return
    if abs(val - ref) > 1e-5:
        fail("%s: mip %s != ref %s" % (name, val, ref))
    # MAX-SAT
    if not run_cli(name, ["/app/maxsat.py", casedir+"/maxsat.txt", outdir+"/ms.json"]):
        return
    exp = ref_maxsat(casedir+"/maxsat.txt")
    try:
        got = json.load(open(outdir+"/ms.json"))
    except Exception:
        fail(name+": maxsat json invalid"); return
    if exp == "HARD_UNSAT":
        if got.get("status") != "HARD_UNSAT":
            fail(name+": maxsat expected HARD_UNSAT, got %r" % (got,))
    else:
        if got.get("status") != "OPTIMAL" or int(got.get("objective")) != exp:
            fail("%s: maxsat objective %r != %r" % (name, got.get("objective"), exp))
    # QUARTIC
    if not run_cli(name, ["/app/quartic.py", casedir+"/quartic.txt", outdir+"/q.json"]):
        return
    try:
        gj = json.load(open(outdir+"/q.json"))
    except Exception:
        fail(name+": quartic json invalid"); return
    reff = ref_quartic(casedir+"/quartic.txt")
    if isinstance(gj, dict):
        obj = gj.get("objective"); gn = gj.get("gradient_norm")
        if obj is None or abs(float(obj)-reff) > 1e-3 * max(1.0, abs(reff)):
            fail("%s: quartic objective %r != ref %r" % (name, obj, reff))
        if gn is None or float(gn) > 0.02:
            fail("%s: quartic gradient_norm %r not stationary" % (name, gn))
    else:
        fail(name+": quartic output wrong shape")
    # CORNERS
    if not run_cli(name, ["/app/corners.py", casedir+"/corners.txt", outdir+"/corn.txt"]):
        return
    exp = ref_corners(casedir+"/corners.txt")
    gotl = [ln.strip() for ln in open(outdir+"/corn.txt") if ln.strip()]
    if gotl != exp:
        fail("%s: corners %r != %r" % (name, gotl, exp))
    # VERDICTS
    if not run_cli(name, ["/app/verdicts.py", casedir+"/verdicts", outdir+"/sat.txt"]):
        return
    exp = ref_verdicts(casedir+"/verdicts")
    gotv = [ln.strip() for ln in open(outdir+"/sat.txt") if ln.strip()]
    if gotv != exp:
        fail("%s: verdicts %r != %r" % (name, gotv, exp))
    # COMPRESS
    if not run_cli(name, ["/app/compress.py", casedir+"/text.txt", casedir+"/ceiling.txt", outdir+"/enc.bin"]):
        return
    try:
        data = open(casedir+'/text.txt','rb').read()
        enc = open(outdir+'/enc.bin','rb').read()
        dec = decode(enc)
        ceil = int(open(casedir+'/ceiling.txt').read().strip())
        if dec != data:
            fail(name+": compress does not decode to source")
        elif len(enc) >= ceil:
            fail("%s: compress size %d not < ceiling %d" % (name, len(enc), ceil))
    except Exception as e:
        fail(name+": compress decode error: "+str(e)[:120])

# ---------------- visible /app deliverables ----------------
for d in ["/app/opt.py","/app/maxsat.py","/app/quartic.py","/app/corners.py",
          "/app/verdicts.py","/app/compress.py",
          "/app/model.mps.optimized.txt","/app/maxsat_solution.json",
          "/app/quartic_solution.json","/app/corners.txt",
          "/app/sat_verdicts.txt","/app/encode.bin"]:
    if not os.path.isfile(d):
        fail("missing deliverable " + d)

# visible deliverables contents must match reference
if os.path.isfile("/app/model.mps.optimized.txt"):
    try:
        v = float(open("/app/model.mps.optimized.txt").read().split("OBJECTIVE")[1].strip())
        if abs(v - ref_mip("/app/case/model.mps")) > 1e-5:
            fail("visible mip file wrong")
    except Exception:
        fail("visible model.mps.optimized.txt unparseable")
if os.path.isfile("/app/maxsat_solution.json"):
    try:
        gj = json.load(open("/app/maxsat_solution.json"))
        exp = ref_maxsat("/app/case/maxsat.txt")
        if exp == "HARD_UNSAT":
            if gj.get("status") != "HARD_UNSAT": fail("visible maxsat should be HARD_UNSAT")
        elif gj.get("objective") != exp: fail("visible maxsat objective mismatch")
    except Exception:
        fail("visible maxsat_solution.json invalid")

# run everything for hidden cases
if os.path.isdir(HID):
    for c in sorted(os.listdir(HID)):
        cd = os.path.join(HID, c)
        if not os.path.isdir(cd) or not os.path.isfile(cd + "/model.mps"):
            continue
        check_case(c, cd, "/tmp/vout_" + c)

print("VERIFY FAILURES: %d" % len(FAIL))
for m in FAIL[:60]:
    print("  -", m)
sys.exit(1 if FAIL else 0)
PY

if [ $? -eq 0 ]; then reward=1; else reward=0; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
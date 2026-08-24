#!/usr/bin/env python3
import math, sys

def load(path):
    W = None
    lines = []
    out = {}
    with open(path) as f:
        for ln in f:
            s = ln.strip()
            if not s or s.startswith('#'):
                continue
            t = s.split()
            if t[0] == 'WIDTH':
                W = int(t[1]); continue
            if t[0] == 'OUT':
                out[int(t[1])] = int(t[2]); continue
            lines.append(t)
    if W is None:
        raise ValueError("no WIDTH line")
    return (W, lines, out)

BINOPS = {
    'ADD': lambda a, b: (a + b),
    'SUB': lambda a, b: (a - b),
    'MUL': lambda a, b: (a * b),
    'AND': lambda a, b: a & b,
    'OR':  lambda a, b: a | b,
    'XOR': lambda a, b: a ^ b,
    'LT':  lambda a, b: 1 if a < b else 0,
    'EQ':  lambda a, b: 1 if a == b else 0,
}

def evaluate(netlist, inputs):
    W, lines, out = netlist
    mask = (1 << W) - 1
    vals = {}
    for toks in lines:
        op = toks[0]; oid = int(toks[1])
        if op == 'IN':
            vals[oid] = inputs[int(toks[2])] & mask
        elif op == 'C':
            v = int(toks[2])
            if not (0 <= v < (1 << W)):
                raise ValueError(("const out of width", v, W))
            vals[oid] = v
        elif op == 'IF':
            c, a, b = map(int, toks[2:5])
            if not (c < oid and a < oid and b < oid):
                raise ValueError(("ordering IF", toks))
            vals[oid] = vals[a] if vals[c] != 0 else vals[b]
        elif op == 'NOT':
            a = int(toks[2])
            if not (a < oid): raise ValueError(("ordering NOT", toks))
            vals[oid] = (~vals[a]) & mask
        elif op == 'SHL':
            a, k = int(toks[2]), int(toks[3])
            if not (a < oid and k < oid): raise ValueError(("ordering SHL", toks))
            vals[oid] = (vals[a] << vals[k]) & mask
        elif op == 'SHR':
            a, k = int(toks[2]), int(toks[3])
            if not (a < oid and k < oid): raise ValueError(("ordering SHR", toks))
            vals[oid] = vals[a] >> vals[k]
        elif op in BINOPS:
            a, b = int(toks[2]), int(toks[3])
            if not (a < oid and b < oid): raise ValueError(("ordering", toks))
            vals[oid] = BINOPS[op](vals[a], vals[b]) & mask
        else:
            raise ValueError(("unknown op", op))
    if 0 not in out:
        raise ValueError("no output port 0")
    return vals[out[0]]

def fib(n):
    a, b = 0, 1
    for _ in range(n):
        a, b = b, a + b
    return a

def main():
    reward = 0.0

    try:
        nl = load('/app/sqrt_32.ng')
        sq_tests = [0,1,2,3,4,7,8,9,15,16,17,24,25,26,49,63,64,65,99,100,
                   255,256,999,1000,4095,4096,4097,65535,65536,65537,100000,
                   (1<<20)-1, 1<<20, (1<<24)-1, (1<<31)-1, 1<<31, (1<<32)-1,
                   1234567890, 3141592653, 4294836225]
        ok_sqrt = True
        for x in sq_tests:
            v = evaluate(nl, [x])
            e = math.isqrt(x)
            if v != e:
                ok_sqrt = False
                print("sqrt mismatch x=%d got=%d want=%d" % (x, v, e))
                break
    except Exception as e:
        print("sqrt netlist error:", repr(e))
        ok_sqrt = False

    try:
        nl = load('/app/fib_64.ng')
        ok_fib = True
        for k in [0,1,2,3,4,5,6,7,8,9,10,11,15,20,25,30,40,50,60,63,64]:
            v = evaluate(nl, [k])
            e = fib(k)
            if v != e:
                ok_fib = False
                print("fib mismatch k=%d got=%d want=%d" % (k, v, e))
                break
    except Exception as e:
        print("fib netlist error:", repr(e))
        ok_fib = False

    if ok_sqrt:
        reward += 0.5
    if ok_fib:
        reward += 0.5

    # keep to 0, 0.5, or 1.0 -> floor at 1.0 cap
    if reward > 1.0: reward = 1.0
    print("REWARD", reward)
    sys.stdout.flush()
    with open("/logs/verifier/reward.txt", "w") as f:
        f.write("%s" % (int(reward) if reward == 1.0 else reward))

main()
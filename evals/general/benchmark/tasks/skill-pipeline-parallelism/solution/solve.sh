#!/bin/bash
set -euo pipefail
python3 - <<'PYEOF'
import multiprocessing as mp

ITEMS = ["  alpha  ", "beta", "  gamma", "delta", " epsilon ", "zeta"]

def stage1(s):
    return s.strip()

def stage2(s):
    return s.upper()

def stage3(s):
    return s + "!"

def worker(inq, outq, fn):
    while True:
        msg = inq.get()
        if msg is None:
            outq.put(None)
            break
        idx, item = msg
        outq.put((idx, fn(item)))

def main():
    ctx = mp.get_context('fork')
    q12, q23, qout = ctx.Queue(), ctx.Queue(), ctx.Queue()
    w1 = ctx.Process(target=worker, args=(q12, q23, stage1))
    w2 = ctx.Process(target=worker, args=(q23, qout, stage2))
    w1.start(); w2.start()

    for i, it in enumerate(ITEMS):
        q12.put((i, it))
    q12.put(None)

    results = [None] * len(ITEMS)
    n_done = 0
    while n_done < len(ITEMS):
        msg = qout.get()
        if msg is None:
            break
        idx, val = msg
        results[idx] = stage3(val)
        n_done += 1

    w1.join(); w2.join()
    with open('/app/out.txt', 'w') as f:
        f.write("\n".join(results) + "\n")
    print("wrote /app/out.txt")

main()
PYEOF
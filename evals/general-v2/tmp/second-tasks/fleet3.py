#!/usr/bin/env python3
"""Fleet driver v3: batches3 (2 comps each), retries built into author_batch3.sh."""
import subprocess, os, re, json, time, sys
from pathlib import Path

ROOT = Path('/Users/ethanewer/pi-setup/evals/general-v2')
BATCHES = sorted((ROOT / 'tmp/second-tasks/batches3').glob('batch_*.json'))
CONC = int(sys.argv[1]) if len(sys.argv) > 1 else 3
TIMEOUT = 5400

def done_cids():
    out = set()
    for f in (ROOT / 'tmp/second-tasks').rglob('agent.out'):
        try:
            for line in f.read_text(errors='ignore').splitlines():
                if line.startswith('RESULT'):
                    m = re.search(r'"cid":"(C-[^"]+)"', line)
                    if m and '"oracle_reward":1.0' in line.replace(' ', '').replace("'", '"'):
                        out.add(m.group(1))
        except Exception:
            pass
    return out

def batch_done(bf, done):
    comps = json.loads(bf.read_text())
    return all(c['id'] in done for c in comps)

procs = {}
while True:
    done = done_cids()
    queue = [b for b in BATCHES if not batch_done(b, done)]
    if not queue and not procs:
        print('FLEET3_COMPLETE', flush=True)
        break
    for p, (bf, start) in list(procs.items()):
        rc = p.poll()
        if rc is not None:
            del procs[p]
            print(f'done rc={rc} {bf.name} elapsed={int(time.time()-start)}s', flush=True)
        elif time.time() - start > TIMEOUT:
            p.kill(); del procs[p]
            print(f'KILLED timeout {bf.name}', flush=True)
    while queue and len(procs) < CONC:
        bf = queue.pop(0)
        out = ROOT / 'tmp/second-tasks' / f'b3-{bf.stem}'
        out.mkdir(parents=True, exist_ok=True)
        p = subprocess.Popen(
            ['bash', str(ROOT / 'tmp/second-tasks/author_batch3.sh'), str(bf)],
            stdout=open(out / 'agent.out', 'w'), stderr=open(out / 'agent.err', 'w'),
            cwd=ROOT)
        procs[p] = (bf, time.time())
        print(f'launch {bf.name} active={len(procs)} queued={len(queue)} done={len(done)}', flush=True)
    time.sleep(15)

print(f'final done={len(done_cids())}', flush=True)

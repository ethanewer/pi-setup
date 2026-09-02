#!/bin/bash
# Real oracle for nova-quarry: write the compact engine, then RUN it on the
# visible fixtures to produce /app/preds.csv. Never reads /tests.
set -eu

cat > /app/engine.py <<'PY'
import json, sys
import numpy as np

def norm(x):
    m = x.mean(-1, keepdims=True)
    v = ((x - m) ** 2).mean(-1, keepdims=True)
    return (x - m) / np.sqrt(v + 1e-5)

def main():
    cfg = json.load(open(sys.argv[1]))
    S = np.load(sys.argv[2])
    data = json.load(open(sys.argv[3]))
    out = sys.argv[5] if len(sys.argv) > 5 else 'preds.csv'
    d, heads, layers = cfg['d'], cfg['heads'], cfg['layers']
    dh = d // heads
    lines = ['sid,pred_token,top_logit']
    for sid, toks in data:
        n = len(toks)
        x = (S['embed'][toks] + S['pos'][:n]).astype(np.float32)
        for i in range(layers):
            h = norm(x)
            q = (h @ S['q%d' % i]).reshape(n, heads, dh).transpose(1, 0, 2)
            k = (h @ S['k%d' % i]).reshape(n, heads, dh).transpose(1, 0, 2)
            v = (h @ S['v%d' % i]).reshape(n, heads, dh).transpose(1, 0, 2)
            a = q @ k.transpose(0, 2, 1) / np.float32(np.sqrt(dh))
            a = np.where(np.triu(np.ones((n, n), bool), 1), np.float32(-1e30), a)
            a = a - a.max(-1, keepdims=True)
            a = np.exp(a)
            a = a / a.sum(-1, keepdims=True)
            x = x + (a @ v).transpose(1, 0, 2).reshape(n, d) @ S['o%d' % i]
            g = np.maximum(x @ S['w1%d' % i], np.float32(0))
            x = x + g @ S['w2%d' % i]
        z = norm(x[-1]) * S['ln_g'] + S['ln_b']
        lg = z @ S['wout'] + S['bout']
        lines.append('%s,%d,%.6f' % (sid, lg.argmax(), lg.max()))
    open(out, 'w').write('\n'.join(lines) + '\n')

main()
PY

python3 -m py_compile /app/engine.py
SZ=$(wc -c < /app/engine.py)
echo "engine bytes: $SZ (cap 3000)"

python3 /app/engine.py /app/fixtures/model.json /app/fixtures/state.npz /app/fixtures/data.json --out /app/preds.csv
echo "solve.sh done"
ls -l /app/engine.py /app/preds.csv

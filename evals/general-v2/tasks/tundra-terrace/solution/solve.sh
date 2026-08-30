#!/bin/bash
set -euo pipefail

# Write the reconstructed transformer engine as the deliverable, then RUN it
# against the fixtures to produce the remaining two deliverables.
cat > /app/reconstruct.py <<'PYEOF'
import argparse, json, numpy as np

def scores(cfg, S, toks):
    H = int(cfg['heads']); D = int(cfg['d']); eps = 1e-5
    t = np.asarray(toks, dtype=np.int64)
    x = S['embed'][t].astype(np.float32); T = x.shape[0]
    x = x + S['pos'][:T].astype(np.float32); Dh = D // H
    for l in range(int(cfg['layers'])):
        m = x.mean(1, keepdims=True); v = x.var(1, keepdims=True)
        n = (x - m) / np.sqrt(v + eps)
        q = n @ S['q%d' % l]; k = n @ S['k%d' % l]; vv = n @ S['v%d' % l]
        q = q.reshape(T, H, Dh).transpose(1, 0, 2)
        k = k.reshape(T, H, Dh).transpose(1, 0, 2)
        vv = vv.reshape(T, H, Dh).transpose(1, 0, 2)
        a = q @ k.transpose(0, 2, 1) / np.sqrt(Dh)
        a = np.exp(a - a.max(-1, keepdims=True)); a = a / a.sum(-1, keepdims=True)
        o = (a @ vv).transpose(1, 0, 2).reshape(T, D)
        x = x + o @ S['o%d' % l]
        h = x @ S['w1%d' % l]
        g = 0.5 * h * (1 + np.tanh(np.sqrt(2.0 / np.pi) * (h + 0.044715 * h * h * h)))
        x = x + g @ S['w2%d' % l]
    z = x[T - 1]
    zn = (z - z.mean()) / np.sqrt(z.var() + eps)
    zn = zn * S['ln_g'] + S['ln_b']
    return float((zn @ S['out']) + S['bout'])

def lowrank(cfg, S):
    names = ['embed', 'pos']
    for l in range(int(cfg['layers'])):
        names += ['q%d' % l, 'k%d' % l, 'v%d' % l, 'o%d' % l, 'w1%d' % l, 'w2%d' % l]
    out = {}
    r = int(cfg['rank'])
    for nm in names:
        M = np.asarray(S[nm], dtype=np.float64)
        rk = min(r, min(M.shape))
        U, Sv, Vt = np.linalg.svd(M, full_matrices=False)
        L = U[:, :rk] * Sv[:rk]
        out[nm + '_L'] = L.astype(np.float32)
        out[nm + '_R'] = Vt[:rk, :].astype(np.float32)
    return out

def main():
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument('config'); ap.add_argument('state'); ap.add_argument('data')
    ap.add_argument('--out', default='preds.csv')
    ap.add_argument('--lowrank', default='lowrank.npz')
    a = ap.parse_args()
    cfg = json.load(open(a.config)); S = np.load(a.state)
    data = json.load(open(a.data))
    with open(a.out, 'w') as f:
        f.write('sid,score\n')
        for sid, toks in data:
            f.write('%d,%.8f\n' % (sid, scores(cfg, S, toks)))
    np.savez_compressed(a.lowrank, **lowrank(cfg, S))

if __name__ == '__main__':
    main()
PYEOF

cd /app
python3 /app/reconstruct.py \
  /app/fixtures/model.json /app/fixtures/state.npz /app/fixtures/data.json \
  --out /app/preds.csv --lowrank /app/lowrank.npz
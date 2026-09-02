#!/bin/bash
# Verifier for nova-quarry: enforces the byte budget and the mandated compile
# command, then EXECUTES /app/engine.py on the visible fixtures and on every
# hidden fixture set in /tests/hidden, comparing against an in-process
# reference implementation. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
R=1
fail() { echo "FAIL: $1" >&2; R=0; }

# ---------- delivery checks ----------
if [ ! -f /app/engine.py ]; then
    fail "missing /app/engine.py"
else
    if ! python3 -m py_compile /app/engine.py 2>/tmp/pyc_err; then
        fail "engine does not compile with the mandated command"
    fi
    SZ=$(wc -c < /app/engine.py)
    if [ "$SZ" -gt 3000 ]; then
        fail "engine exceeds byte budget ($SZ > 3000)"
    fi
fi

cat > /tmp/ref_check.py <<'PY'
import json, os, subprocess, sys
import numpy as np

CAP = 3000


def norm(x):
    m = x.mean(-1, keepdims=True)
    v = ((x - m) ** 2).mean(-1, keepdims=True)
    return (x - m) / np.sqrt(v + 1e-5)


def reference(cfg, S, data):
    d, heads, layers = cfg['d'], cfg['heads'], cfg['layers']
    dh = d // heads
    rows = []
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
        rows.append((sid, int(lg.argmax()), float(lg.max())))
    return rows


def check_case(engine, mdir, label):
    """Run the engine on one fixture set and compare with the reference."""
    mp = os.path.join(mdir, 'model.json')
    sp = os.path.join(mdir, 'state.npz')
    dp = os.path.join(mdir, 'data.json')
    out = '/tmp/nq_out_%s.csv' % label
    if os.path.exists(out):
        os.remove(out)
    try:
        r = subprocess.run(
            ['python3', engine, mp, sp, dp, '--out', out],
            capture_output=True, text=True, timeout=120)
    except Exception as e:
        print('FAIL(%s): engine run raised %s' % (label, e))
        return False
    if r.returncode != 0:
        print('FAIL(%s): engine exited %d' % (label, r.returncode))
        return False
    if not os.path.isfile(out):
        print('FAIL(%s): no output written' % label)
        return False
    try:
        cfg = json.load(open(mp))
        S = np.load(sp)
        data = json.load(open(dp))
        want = reference(cfg, S, data)
        lines = open(out).read().splitlines()
    except Exception as e:
        print('FAIL(%s): unreadable fixture/output: %s' % (label, e))
        return False
    if not lines or lines[0].strip() != 'sid,pred_token,top_logit':
        print('FAIL(%s): bad header %r' % (label, lines[0] if lines else ''))
        return False
    rows = [l for l in lines[1:] if l.strip()]
    if len(rows) != len(want):
        print('FAIL(%s): row count %d != %d' % (label, len(rows), len(want)))
        return False
    preds = []
    for row, (sid, pt, tl) in zip(rows, want):
        parts = row.split(',')
        if len(parts) != 3:
            print('FAIL(%s): malformed row %r' % (label, row))
            return False
        try:
            gs, gp, gv = parts[0], int(parts[1]), float(parts[2])
        except ValueError:
            print('FAIL(%s): unparseable row %r' % (label, row))
            return False
        if gs != sid:
            print('FAIL(%s): sid/order mismatch %r vs %r' % (label, gs, sid))
            return False
        if gp != pt:
            print('FAIL(%s): pred_token %d != %d' % (label, gp, pt))
            return False
        if abs(gv - tl) > 2e-3:
            print('FAIL(%s): top_logit %.6f != %.6f' % (label, gv, tl))
            return False
        preds.append(gp)
    if len(set(preds)) < 2:
        print('FAIL(%s): predictions are uniform' % label)
        return False
    print('OK(%s): %d rows' % (label, len(rows)))
    return True


def main():
    engine = '/app/engine.py'
    if not os.path.isfile(engine):
        print('FAIL: missing engine')
        return 1
    try:
        if os.path.getsize(engine) > CAP:
            print('FAIL: byte budget exceeded')
            return 1
    except OSError:
        print('FAIL: engine unreadable')
        return 1
    ok = True
    if os.path.isdir('/app/fixtures'):
        ok &= check_case(engine, '/app/fixtures', 'visible')
    else:
        ok = False
        print('FAIL: visible fixtures missing')
    hd = '/tests/hidden'
    cases = sorted(os.listdir(hd)) if os.path.isdir(hd) else []
    if not cases:
        print('FAIL: no hidden cases')
        ok = False
    for c in cases:
        mdir = os.path.join(hd, c)
        if not all(os.path.isfile(os.path.join(mdir, f))
                   for f in ('model.json', 'state.npz', 'data.json')):
            print('FAIL(%s): malformed hidden case' % c)
            ok = False
            continue
        ok &= check_case(engine, mdir, c)
    # /app/preds.csv deliverable must match the visible reference
    try:
        cfg = json.load(open('/app/fixtures/model.json'))
        S = np.load('/app/fixtures/state.npz')
        data = json.load(open('/app/fixtures/data.json'))
        want = reference(cfg, S, data)
        lines = open('/app/preds.csv').read().splitlines()
        rows = [l for l in lines[1:] if l.strip()]
        okdel = (lines and lines[0].strip() == 'sid,pred_token,top_logit'
                 and len(rows) == len(want))
        if okdel:
            for row, (sid, pt, tl) in zip(rows, want):
                p = row.split(',')
                if len(p) != 3 or p[0] != sid or int(p[1]) != pt \
                        or abs(float(p[2]) - tl) > 2e-3:
                    okdel = False
                    break
        if not okdel:
            print('FAIL: /app/preds.csv does not match visible reference')
            ok = False
        else:
            print('OK(preds.csv)')
    except Exception as e:
        print('FAIL: /app/preds.csv check raised %s' % e)
        ok = False
    return 0 if ok else 1


sys.exit(main())
PY

if python3 /tmp/ref_check.py; then R=1; else R=0; fi

echo "$R" > /logs/verifier/reward.txt
exit 0

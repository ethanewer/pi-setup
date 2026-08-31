#!/bin/bash
# Verifier for cirrus-gauge (executes-deliverable).
# Executes /app/gen_config.py on the visible parameters and on every hidden
# case under /tests/hidden, parses the generated prototxt and enforces the
# solver/network contract (CPU mode, capped max_iter, data-layer wiring,
# determinism). Writes 1/0 to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
reward=0

if python3 - <<'PY'
import json, os, shutil, subprocess, sys

GEN = "/app/gen_config.py"
SHIPPED_OUT = "/app/out"
SHIPPED_SOLVER = "/app/out/solver.prototxt"
SHIPPED_TRAIN = "/app/out/train_net.prototxt"
SHIPPED_TEST = "/app/out/test_net.prototxt"
CAP = 1000


# ---------- minimal prototxt parser ----------
def tokenize(text):
    toks = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == '#':
            while i < n and text[i] != '\n':
                i += 1
        elif c in ' \t\r\n':
            i += 1
        elif c in '{}:':
            toks.append(c)
            i += 1
        elif c == '"':
            j = i + 1
            while j < n and text[j] != '"':
                j += 1
            toks.append(('str', text[i + 1:j]))
            i = j + 1
        else:
            j = i
            while j < n and text[j] not in ' \t\r\n{}:#"':
                j += 1
            toks.append(text[i:j])
            i = j
    return toks


def parse_block(toks, i, obj):
    while i < len(toks):
        t = toks[i]
        if t == '}':
            return i + 1
        key = t[1] if isinstance(t, tuple) else t
        i += 1
        if i >= len(toks):
            raise ValueError('truncated prototxt')
        if toks[i] == ':':
            val = toks[i + 1]
            i += 2
            obj.setdefault(key, []).append(val[1] if isinstance(val, tuple) else val)
        elif toks[i] == '{':
            child = {}
            obj.setdefault(key, []).append(child)
            i = parse_block(toks, i + 1, child)
        else:
            raise ValueError('unexpected token %r' % (toks[i],))
    return i


def parse_prototxt(path):
    with open(path, 'r', encoding='utf-8') as fh:
        obj = {}
        parse_block(tokenize(fh.read()), 0, obj)
    return obj


def one(obj, key):
    vals = obj.get(key)
    return vals[0] if vals else None


def to_int(v):
    return int(str(v))


def to_float(v):
    return float(str(v))


def phase_of(layer):
    inc = layer.get('include') or []
    if not inc or not isinstance(inc[0], dict):
        return None
    return one(inc[0], 'phase')


def validate_outputs(abs_root, batch, max_iter, abs_out):
    """Structural checks on the three prototxt files inside abs_out."""
    bad = []
    train_path = os.path.join(abs_out, 'train_net.prototxt')
    test_path = os.path.join(abs_out, 'test_net.prototxt')

    # ---- solver ----
    sp = os.path.join(abs_out, 'solver.prototxt')
    if not os.path.isfile(sp):
        return ['missing solver.prototxt']
    try:
        sol = parse_prototxt(sp)
    except Exception as exc:
        return ['solver.prototxt unparseable: %r' % (exc,)]
    if one(sol, 'net') != train_path:
        bad.append('solver net %r != %s' % (one(sol, 'net'), train_path))
    if one(sol, 'test_net') != test_path:
        bad.append('solver test_net %r != %s' % (one(sol, 'test_net'), test_path))
    want_max = min(max_iter, CAP)
    try:
        if to_int(one(sol, 'max_iter')) != want_max:
            bad.append('max_iter %r != capped %d' % (one(sol, 'max_iter'), want_max))
    except Exception:
        bad.append('max_iter not an integer')
    if str(one(sol, 'solver_mode')).upper() != 'CPU':
        bad.append('solver_mode %r is not CPU' % (one(sol, 'solver_mode'),))
    try:
        if not to_float(one(sol, 'base_lr')) > 0:
            bad.append('base_lr not positive')
    except Exception:
        bad.append('base_lr not a positive float')
    for key in ('test_iter', 'test_interval', 'display'):
        try:
            if to_int(one(sol, key)) < 1:
                bad.append('%s not positive' % key)
        except Exception:
            bad.append('%s not an integer' % key)
    prefix = one(sol, 'snapshot_prefix')
    if not prefix or not str(prefix).startswith(abs_out + os.sep):
        bad.append('snapshot_prefix %r outside out_dir' % (prefix,))
    if str(one(sol, 'solver_type')).upper() != 'SGD':
        bad.append('solver_type %r is not SGD' % (one(sol, 'solver_type'),))

    # ---- nets ----
    for tag, path, want_file, want_phase in (
            ('train', train_path, 'train_list.txt', 'TRAIN'),
            ('test', test_path, 'test_list.txt', 'TEST')):
        if not os.path.isfile(path):
            bad.append('missing %s' % path)
            continue
        try:
            net = parse_prototxt(path)
        except Exception as exc:
            bad.append('%s unparseable: %r' % (path, exc))
            continue
        ls = net.get('layer') or []
        names = [one(l, 'name') for l in ls]
        if len(names) != len(set(names)) or None in names:
            bad.append('%s net has duplicate/missing layer names' % tag)
        types = [str(one(l, 'type')) for l in ls]
        if 'Convolution' not in types:
            bad.append('%s net has no Convolution layer' % tag)
        if 'SoftmaxWithLoss' not in types:
            bad.append('%s net has no SoftmaxWithLoss layer' % tag)
        if tag == 'test' and 'Accuracy' not in types:
            bad.append('test net has no Accuracy layer')
        data_ok = False
        for l in ls:
            if str(one(l, 'type')) not in ('ImageData', 'Data'):
                continue
            inc = (l.get('include') or [{}])[0]
            if one(inc, 'phase') != want_phase:
                continue
            idp = (l.get('image_data_param') or [{}])[0]
            src = one(idp, 'source')
            try:
                bs = to_int(one(idp, 'batch_size'))
            except Exception:
                bad.append('%s data layer batch_size not an integer' % tag)
                continue
            if src == os.path.join(abs_root, want_file) and bs == batch:
                data_ok = True
        if not data_ok:
            bad.append('%s net data layer (phase %s) wrong source/batch'
                       % (tag, want_phase))
    return bad


def run_and_check(args, data_root, out_dir):
    """Run gen_config with args; returns failure list."""
    bad = []
    if os.path.isdir(out_dir):
        shutil.rmtree(out_dir)
    cmd = [sys.executable, GEN, data_root, str(args['max_iter']),
           str(args['batch']), out_dir]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=120, cwd='/app')
    if not args.get('expect_ok', True):
        if r.returncode == 0:
            bad.append('invalid args %r: expected non-zero exit' % (args,))
        elif os.path.isfile(os.path.join(out_dir, 'solver.prototxt')):
            bad.append('invalid args %r: solver written anyway' % (args,))
        return bad
    if r.returncode != 0:
        return ['gen_config failed (%s): %s' % (args, r.stderr[:200])]
    abs_out = os.path.abspath(out_dir)
    bad.extend(validate_outputs(os.path.abspath(data_root), args['batch'],
                                args['max_iter'], abs_out))
    # determinism: same args, same out_dir -> byte-identical files
    names = ('solver.prototxt', 'train_net.prototxt', 'test_net.prototxt')
    snap = {}
    for nm in names:
        p = os.path.join(abs_out, nm)
        if os.path.isfile(p):
            with open(p, 'rb') as fh:
                snap[nm] = fh.read()
    r2 = subprocess.run(cmd, capture_output=True, text=True, timeout=120, cwd='/app')
    if r2.returncode != 0:
        bad.append('determinism rerun failed')
    else:
        for nm in names:
            p = os.path.join(abs_out, nm)
            if not os.path.isfile(p):
                bad.append('missing %s after rerun' % nm)
                continue
            with open(p, 'rb') as fh:
                if fh.read() != snap.get(nm):
                    bad.append('rerun not byte-identical: %s' % nm)
    return bad


failures = []
if not os.path.isfile(GEN):
    failures.append('missing /app/gen_config.py')

# --- visible configuration ---
vis = {'max_iter': 400, 'batch': 16}
if os.path.isdir('/app/data/mini'):
    failures.extend('visible: ' + b for b in
                    run_and_check(vis, '/app/data/mini', '/tmp/cirrus_vis'))
    # shipped /app/out must satisfy the same structural contract
    if not all(os.path.isfile(p) for p in
               (SHIPPED_SOLVER, SHIPPED_TRAIN, SHIPPED_TEST)):
        failures.append('shipped /app/out is missing one of '
                        'solver.prototxt / train_net.prototxt / test_net.prototxt')
    if os.path.isdir(SHIPPED_OUT):
        failures.extend('shipped /app/out: ' + b for b in
                        validate_outputs('/app/data/mini', 16, 400, SHIPPED_OUT))
    else:
        failures.append('missing shipped /app/out directory')

# --- hidden cases ---
hidden_dir = '/tests/hidden'
if not os.path.isdir(hidden_dir):
    failures.append('no hidden cases present')
else:
    cases = sorted(d for d in os.listdir(hidden_dir)
                   if os.path.isdir(os.path.join(hidden_dir, d)))
    if not cases:
        failures.append('no hidden cases present')
    for c in cases:
        base = os.path.join(hidden_dir, c)
        try:
            with open(os.path.join(base, 'args.json')) as fh:
                args = json.load(fh)
        except Exception:
            failures.append("hidden '%s': args.json unreadable" % c)
            continue
        data_src = os.path.join(base, 'data')
        if not os.path.isdir(data_src):
            failures.append("hidden '%s': missing data dir" % c)
            continue
        data_root = '/tmp/cirrus_h_%s_data' % c
        if os.path.isdir(data_root):
            shutil.rmtree(data_root)
        shutil.copytree(data_src, data_root)
        bad = run_and_check(args, data_root, '/tmp/cirrus_h_%s_out' % c)
        failures.extend('hidden %s: %s' % (c, b) for b in bad)

print('verify failures:', failures)
sys.exit(1 if failures else 0)
PY
then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0

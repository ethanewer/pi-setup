#!/bin/bash
# Cinder Loom verifier. Enforces the no-modify rule on /app/store.img, checks
# the visible-case deliverables, and EXECUTES the deliverable tool /app/carve.py
# on the visible store and on every hidden store in /tests/hidden, byte-comparing
# the recovered files and checking for extras. Writes reward to reward.txt.
set -u

mkdir -p /logs/verifier
reward=0
ok=1
fail() { echo "FAIL: $*" >&2; ok=0; }

PRISTINE_STORE_SHA="fc093a0b5de3a0ed181e87eace5b9b03f9b31f694b517c60f904cb246b046af1"

if [ ! -f /app/store.img ]; then
    fail "no-modify: /app/store.img missing"
else
    actual="$(sha256sum /app/store.img | awk '{print $1}')"
    [ "$actual" = "$PRISTINE_STORE_SHA" ] || fail "no-modify: /app/store.img was modified"
fi

[ -f /app/carve.py ] || fail "missing deliverable /app/carve.py"
[ -d /app/recovered ] || fail "missing deliverable /app/recovered"

# ---- visible deliverable: /app/recovered must match the visible ground truth,
# ---- with nothing extra in the directory.
python3 - <<'PY' || fail "visible /app/recovered mismatch"
import hashlib, json, os
exp = json.load(open('/tests/expected.json'))
d = '/app/recovered'
got = sorted(os.listdir(d))
want = sorted(exp.keys())
assert got == want, ('directory contents', got, want)
for name, meta in exp.items():
    b = open(os.path.join(d, name), 'rb').read()
    assert len(b) == meta['size'], (name, 'size', len(b), meta['size'])
    assert hashlib.sha256(b).hexdigest() == meta['sha256'], (name, 'sha256')
print('visible /app/recovered OK:', want)
PY

# ---- execute the deliverable on the visible store (fresh temp outdir) ----
if [ -f /app/carve.py ]; then
    W=$(mktemp -d)
    python3 /app/carve.py /app/store.img "$W/vis" > "$W/vis.out" 2>&1 \
        || fail "carve.py failed on visible store"
    grep -q "^TOTAL=" "$W/vis.out" || fail "carve.py did not print TOTAL on visible"
    python3 - "$W/vis" <<'PY' || fail "visible rerun mismatch"
import hashlib, json, os, sys
exp = json.load(open('/tests/expected.json'))
d = sys.argv[1]
assert sorted(os.listdir(d)) == sorted(exp.keys()), (sorted(os.listdir(d)), sorted(exp.keys()))
for name, meta in exp.items():
    b = open(os.path.join(d, name), 'rb').read()
    assert hashlib.sha256(b).hexdigest() == meta['sha256'], (name, 'sha256')
print('visible rerun OK')
PY
    rm -rf "$W"
fi

# ---- hidden stores: execute the deliverable, byte-compare, check no extras ----
python3 - <<'PY' || fail "hidden cases failed"
import hashlib, os, shutil, subprocess, sys, tempfile

HIDDEN = '/tests/hidden'
failed = []

if not os.path.isdir(HIDDEN):
    failed.append('no /tests/hidden')
else:
    cases = sorted(d for d in os.listdir(HIDDEN)
                   if os.path.isdir(os.path.join(HIDDEN, d)))
    if not cases:
        failed.append('no hidden cases')
    for case in cases:
        base = os.path.join(HIDDEN, case)
        store = os.path.join(base, 'store.bin')
        expdir = os.path.join(base, 'expected')
        if not (os.path.isfile(store) and os.path.isdir(expdir)):
            failed.append('%s: malformed case' % case)
            continue
        work = tempfile.mkdtemp(prefix='loomverify-')
        out = os.path.join(work, 'out')
        r = subprocess.run([sys.executable, '/app/carve.py', store, out],
                           capture_output=True, text=True, timeout=120)
        try:
            if r.returncode != 0:
                failed.append('%s: carve.py exited %d' % (case, r.returncode))
                continue
            want = sorted(os.listdir(expdir))
            got = sorted(os.listdir(out))
            if got != want:
                failed.append('%s: contents %s != %s' % (case, got, want))
                continue
            for name in want:
                a = open(os.path.join(out, name), 'rb').read()
                b = open(os.path.join(expdir, name), 'rb').read()
                if a != b:
                    failed.append('%s/%s: byte mismatch' % (case, name))
            if not any(l.startswith('TOTAL=') for l in r.stdout.splitlines()):
                failed.append('%s: no TOTAL line' % case)
        finally:
            shutil.rmtree(work, ignore_errors=True)

if failed:
    print('hidden failures:', failed)
    raise SystemExit(1)
print('all hidden cases OK')
PY

[ "$ok" -eq 1 ] && reward=1
echo "$reward" > /logs/verifier/reward.txt
echo "reward=$reward" >&2
exit 0

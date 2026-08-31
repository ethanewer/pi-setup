#!/bin/bash
# maple-vellum verifier (executes-deliverable).
# Checks the deliverables, ENFORCES the no-modify rule on the shipped
# /app/store, verifies /app/restored against the ground-truth manifest, and
# EXECUTES /app/reassemble.py on every hidden store (including a corrupted
# one). Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -uo pipefail
mkdir -p /logs/verifier
reward=1
fail(){ echo "FAIL: $*" >&2; reward=0; }

[ -f /app/reassemble.py ] || fail "missing /app/reassemble.py"
[ -d /app/restored ]       || fail "missing /app/restored"
[ -f /app/store/manifest.json ] || fail "shipped /app/store is missing"
if [ "$reward" -eq 0 ]; then echo "0" >/logs/verifier/reward.txt; echo "final-reward=0"; exit 0; fi

# ---- 0. no-modify guard on the shipped store --------------------------- #
STORE_SIG=$(cd /app && find store -type f -print0 | sort -z | xargs -0 sha256sum \
  | sha256sum | cut -d' ' -f1)
if [ "$STORE_SIG" != "7d9801ee35a1ce468aa07ae0bf908503ed593d569614623b6f6f2025b25cfeec" ]; then
  fail "/app/store was modified (protected input)"
fi
if [ "$reward" -eq 0 ]; then echo "0" >/logs/verifier/reward.txt; echo "final-reward=0"; exit 0; fi

# ---- 1+2. verify visible restoration + run on hidden stores ------------ #
PY=$(cat <<'PY'
import hashlib, json, os, shutil, subprocess, sys, tempfile

REASM = '/app/reassemble.py'


def tree_signature(root):
    """Exact signature of a restored tree: dirs set + {relpath: sha256}."""
    if not os.path.isdir(root):
        return None
    dirs = set()
    files = {}
    for dirpath, dirnames, filenames in os.walk(root):
        for dn in dirnames:
            full = os.path.join(dirpath, dn)
            dirs.add(os.path.relpath(full, root))
        for fn in filenames:
            full = os.path.join(dirpath, fn)
            rel = os.path.relpath(full, root)
            with open(full, 'rb') as f:
                files[rel] = hashlib.sha256(f.read()).hexdigest()
    return {'dirs': dirs, 'files': files}


def check_ok(out_root, expected):
    sig = tree_signature(out_root)
    if sig is None:
        return 'output tree %s was not created' % out_root
    want_dirs = set(expected['dirs'])
    # parents implied by file paths count as dirs in the signature; require
    # exactly the declared dirs plus any parents of declared files
    implied = set()
    for rel in expected['files']:
        parts = rel.split('/')[:-1]
        for i in range(len(parts)):
            implied.add('/'.join(parts[:i + 1]))
    if not want_dirs <= sig['dirs']:
        return ('missing dirs: %s' % sorted(want_dirs - sig['dirs'])[:5])
    extra_dirs = sig['dirs'] - want_dirs - implied
    if extra_dirs:
        return 'unexpected extra dirs: %s' % sorted(extra_dirs)[:5]
    if set(sig['files']) != set(expected['files']):
        missing = sorted(set(expected['files']) - set(sig['files']))[:5]
        extra = sorted(set(sig['files']) - set(expected['files']))[:5]
        return 'file set mismatch (missing %s, extra %s)' % (missing, extra)
    for rel, want in expected['files'].items():
        if sig['files'][rel] != want:
            return 'hash mismatch for %r' % rel
    return None


fails = []

# ---- visible restoration: /app/restored vs ground truth ---------------- #
try:
    exp = json.load(open('/tests/expected.json'))
    err = check_ok('/app/restored', exp)
    if err:
        fails.append('visible: /app/restored %s' % err)
except Exception as exc:  # guarded parse
    fails.append('visible: expected/parse error: %r' % exc)

# ---- hidden stores ----------------------------------------------------- #
hroot = '/tests/hidden'
cases = sorted(d for d in os.listdir(hroot)
               if os.path.isdir(os.path.join(hroot, d))) if os.path.isdir(hroot) else []
if not cases:
    fails.append('no hidden cases present')
for case in cases:
    base = os.path.join(hroot, case)
    store = os.path.join(base, 'store')
    try:
        exp = json.load(open(os.path.join(base, 'expected.json')))
    except Exception as exc:
        fails.append('%s: unreadable expected.json (%r)' % (case, exc))
        continue
    outdir = tempfile.mkdtemp(prefix='mv-out-')
    out = os.path.join(outdir, 'out')
    try:
        r = subprocess.run([sys.executable, REASM, '--store', store, '--out', out],
                           capture_output=True, timeout=120)
    except Exception as exc:
        fails.append('%s: reassemble.py run error %r' % (case, exc))
        shutil.rmtree(outdir, ignore_errors=True)
        continue
    if exp.get('status') == 'error':
        if r.returncode == 0:
            fails.append('%s: expected non-zero exit for corrupted store, got 0' % case)
        elif os.path.isdir(out) and tree_signature(out) and tree_signature(out)['files']:
            # a corrupted store must not silently produce a full wrong tree
            fails.append('%s: wrote a file tree despite corruption' % case)
    else:
        if r.returncode != 0:
            fails.append('%s: rc=%d stderr=%r' % (case, r.returncode, r.stderr.decode()[:120]))
        else:
            err = check_ok(out, exp)
            if err:
                fails.append('%s: %s' % (case, err))
    shutil.rmtree(outdir, ignore_errors=True)

print(' ; '.join(fails) if fails else 'HIDDEN-CASES-PASS')
sys.exit(1 if fails else 0)
PY
)
if python3 -c "$PY"; then :; else fail "functional checks failed"; fi

# ---- finalize ------------------------------------------------------------ #
echo "final-reward=$reward"
echo "$reward" >/logs/verifier/reward.txt
exit 0

#!/bin/bash
# Verifier for cobalt-manifest (executes-deliverable).
# Executes /app/solve.py on the visible manifest and on every hidden instance
# under /tests/hidden, independently re-derives the unique optimum (exact
# enumeration of integer allocations with equality-sum constraints) and
# compares. Writes 1/0 to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
reward=0

PRISTINE_MANIFEST_SHA="182f73f27015af1cbccf4ac1365d5c9a2c2024c49d84bb15845ea1d402716713"

no_modify_broken=0
if [ ! -f /app/manifest.json ]; then
    echo "no-modify: /app/manifest.json missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/manifest.json | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_MANIFEST_SHA" ]; then
        echo "no-modify: /app/manifest.json was modified" >&2
        no_modify_broken=1
    fi
fi

python3 - "$no_modify_broken" <<'PY'
import json, os, subprocess, sys

SOLVE = "/app/solve.py"
RESULT = "/app/manifest_result.json"
no_modify_broken = int(sys.argv[1])


def reference(manifest):
    """Independent re-derivation of the unique optimum.

    Full enumeration of nonnegative integer quantity vectors with
    count/mass pruning. Returns (cost, -science, q-tuple) or None if
    infeasible.
    """
    K = int(manifest['containers'])
    W = int(manifest['mass'])
    V = int(manifest['volume_limit'])
    cargo = manifest['cargo']
    n = len(cargo)
    best = [None]
    q = []

    def rec(i, k, w, cost, sci, vol):
        if i == n:
            if k == K and w == W and vol <= V:
                cand = (cost, -sci, tuple(q))
                if best[0] is None or cand < best[0]:
                    best[0] = cand
            return
        m = int(cargo[i]['mass'])
        maxq = K - k
        if m > 0:
            if W - w < 0:
                return
            maxq = min(maxq, (W - w) // m)
        for qv in range(maxq + 1):
            q.append(qv)
            rec(i + 1, k + qv, w + qv * m,
                cost + qv * int(cargo[i]['cost']),
                sci + qv * int(cargo[i]['science']),
                vol + qv * int(cargo[i]['volume']))
            q.pop()

    rec(0, 0, 0, 0, 0, 0)
    return best[0]


def check_result(got, manifest):
    """Validate one solver output against the manifest. Returns error or None."""
    if not isinstance(got, dict):
        return 'result is not a dict'
    K = int(manifest['containers'])
    W = int(manifest['mass'])
    V = int(manifest['volume_limit'])
    cargo = manifest['cargo']
    names = [c['name'] for c in cargo]

    ref = reference(manifest)
    if ref is None:
        if set(got.keys()) != {'infeasible', 'quantities'}:
            return 'expected infeasible form, got keys %r' % sorted(got.keys())
        if got.get('infeasible') is not True or got.get('quantities') != {}:
            return 'malformed infeasible result'
        return None

    if set(got.keys()) != {'cost', 'science', 'mass', 'volume', 'quantities'}:
        return 'keys %r != expected result shape' % sorted(got.keys())
    qmap = got['quantities']
    if not isinstance(qmap, dict) or set(qmap.keys()) != set(names):
        return 'quantities keys %r != cargo names' % (sorted(qmap) if isinstance(qmap, dict) else qmap,)
    vals = {}
    for k in ('cost', 'science', 'mass', 'volume'):
        v = got[k]
        if isinstance(v, bool) or not isinstance(v, int):
            return '%s is not an int (fractional/float results are invalid)' % k
        vals[k] = v
    for name, v in qmap.items():
        if isinstance(v, bool) or not isinstance(v, int) or v < 0:
            return 'quantity %r is not a nonnegative int' % (name,)
    qtuple = tuple(qmap[name] for name in names)
    count = sum(qtuple)
    mass = sum(int(c['mass']) * q for c, q in zip(cargo, qtuple))
    volume = sum(int(c['volume']) * q for c, q in zip(cargo, qtuple))
    cost = sum(int(c['cost']) * q for c, q in zip(cargo, qtuple))
    science = sum(int(c['science']) * q for c, q in zip(cargo, qtuple))
    if count != K:
        return 'count %d != containers %d (equality-sum violated)' % (count, K)
    if mass != W:
        return 'mass %d != mass target %d (equality-sum violated)' % (mass, W)
    if volume > V:
        return 'volume %d exceeds volume_limit %d' % (volume, V)
    if vals['mass'] != mass or vals['volume'] != volume or \
       vals['cost'] != cost or vals['science'] != science:
        return 'reported totals do not match recomputation'
    if (cost, -science, qtuple) != ref:
        return 'allocation (cost=%d, science=%d) is not the unique optimum' % (cost, science)
    return None


def run_case(path):
    """Run the deliverable on a manifest file; returns (got, error)."""
    out = '/tmp/cobalt_out_%d.json' % os.getpid()
    if os.path.exists(out):
        os.remove(out)
    try:
        r = subprocess.run([sys.executable, SOLVE, path, out],
                           capture_output=True, text=True, timeout=90)
    except Exception as exc:
        return None, 'solve.py raised %r' % (exc,)
    if r.returncode != 0:
        return None, 'solve.py exited %d: %s' % (r.returncode, r.stderr[:200])
    try:
        with open(out) as fh:
            return json.load(fh), None
    except Exception as exc:
        return None, 'output unreadable: %r' % (exc,)


failures = []
if no_modify_broken:
    failures.append('visible manifest modified or missing (no-modify rule)')

if not os.path.isfile(SOLVE):
    failures.append('missing /app/solve.py')
else:
    # --- visible case ---
    if os.path.isfile('/app/manifest.json'):
        got, err = run_case('/app/manifest.json')
        if err:
            failures.append('visible: ' + err)
        else:
            msg = check_result(got, json.load(open('/app/manifest.json')))
            if msg:
                failures.append('visible: ' + msg)
        # shipped /app/manifest_result.json must match too
        if not os.path.isfile(RESULT):
            failures.append('missing /app/manifest_result.json')
        else:
            try:
                with open(RESULT) as fh:
                    shipped = json.load(fh)
                msg = check_result(shipped, json.load(open('/app/manifest.json')))
                if msg:
                    failures.append('shipped manifest_result.json: ' + msg)
            except Exception as exc:
                failures.append('manifest_result.json unreadable: %r' % (exc,))

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
            mf = os.path.join(hidden_dir, c, 'manifest.json')
            if not os.path.isfile(mf):
                failures.append("hidden '%s': missing manifest.json" % c)
                continue
            got, err = run_case(mf)
            if err:
                failures.append("hidden '%s': %s" % (c, err))
                continue
            msg = check_result(got, json.load(open(mf)))
            if msg:
                failures.append("hidden '%s': %s" % (c, msg))

print('verify failures:', failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
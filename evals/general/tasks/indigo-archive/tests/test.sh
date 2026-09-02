#!/bin/bash
# Verifier for indigo-archive: EXECUTES the deliverable /app/recover.py on the
# visible volume and on every hidden volume in /tests/hidden, compares the
# recovered JSON and SHA-256 evidence exactly, and enforces the no-modify rule
# on /app/volume.bin. Writes a numeric reward to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
reward=0

work=/tmp/indigo_verify
rm -rf "$work"; mkdir -p "$work"
PY=/app/recover.py

# Pristine sha256 of /app/volume.bin (the supplied visible fixture).
PRISTINE_VOLUME_SHA="740a0fe64effe5d2329d83996e2ebbe8185ad58b8abc8cdc7a4856563e2f8b84"

fail() { echo "VERIFY FAIL: $1" >&2; }

if [ ! -f "$PY" ]; then
    fail "deliverable /app/recover.py not present"
    echo "$reward" > /logs/verifier/reward.txt
    exit 0
fi

# run_case <volume> <expected_recovered> <label>
run_case() {
    local vol="$1" expected="$2" label="$3"
    local rec_out="$work/rec.$label.json" ev_out="$work/ev.$label.json"
    if ! python3 "$PY" "$vol" "$rec_out" "$ev_out" >"$work/serr.$label" 2>&1; then
        fail "$label: /app/recover.py exited non-zero"
        return 1
    fi
    if [ ! -s "$rec_out" ]; then fail "$label: no recovered.json written"; return 1; fi
    if [ ! -s "$ev_out" ]; then fail "$label: no evidence.json written"; return 1; fi
    # (1) recovered records must match the expected JSON exactly.
    if ! python3 - "$rec_out" "$expected" >&2 <<'PY'
import json, sys
got = json.load(open(sys.argv[1]))
want = json.load(open(sys.argv[2]))
ok = got.get('records') == want.get('records') and got.get('status') == want.get('status')
if not ok:
    print('  expected:', json.dumps(want), file=sys.stderr)
    print('  got:     ', json.dumps(got), file=sys.stderr)
sys.exit(0 if ok else 1)
PY
then
        fail "$label: recovered JSON mismatch"
        return 1
    fi
    # (2) evidence hashes must equal the hashes derived from the input + expected.
    if ! python3 - "$vol" "$ev_out" "$expected" >&2 <<'PY'
import json, sys, hashlib
data = open(sys.argv[1], 'rb').read()
ev = json.load(open(sys.argv[2]))
want = json.load(open(sys.argv[3]))
exp_image = hashlib.sha256(data).hexdigest()
payloads = ''.join(r['text'] for r in want['records']).encode('utf-8')
exp_rec = hashlib.sha256(payloads).hexdigest()
ok = exp_image == ev.get('image_sha256') and exp_rec == ev.get('records_sha256')
if not ok:
    print('  want image=%s got=%s' % (exp_image, ev.get('image_sha256')), file=sys.stderr)
    print('  want recs =%s got=%s' % (exp_rec, ev.get('records_sha256')), file=sys.stderr)
sys.exit(0 if ok else 1)
PY
then
        fail "$label: evidence hashes mismatch"
        return 1
    fi
    return 0
}

all_ok=1

# --- no-modify guard: /app/volume.bin must be byte-identical to the fixture ---
if [ -f /app/volume.bin ]; then
    actual="$(sha256sum /app/volume.bin | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_VOLUME_SHA" ]; then
        fail "visible input /app/volume.bin was modified (no-modify rule)"
        all_ok=0
    fi
else
    fail "visible input /app/volume.bin missing"
    all_ok=0
fi

# --- visible case ---
if [ -f /app/volume.bin ] && [ -f /tests/expected.json ]; then
    run_case /app/volume.bin /tests/expected.json visible || all_ok=0
else
    fail "visible case files missing"
    all_ok=0
fi

# --- hidden cases ---
if [ -d /tests/hidden ]; then
    n=0
    for bin in /tests/hidden/*.volume.bin; do
        [ -e "$bin" ] || continue
        base="${bin%.volume.bin}"
        exp="$base.expected.json"
        [ -f "$exp" ] || { fail "missing expected for $base"; all_ok=0; continue; }
        label="$(basename "$base")"
        run_case "$bin" "$exp" "$label" || all_ok=0
        n=$((n+1))
    done
    if [ "$n" -lt 1 ]; then
        fail "no hidden cases found"
        all_ok=0
    fi
else
    fail "no /tests/hidden directory"
    all_ok=0
fi

# --- visible-case deliverables /app/recovered.json and /app/evidence.json ---
# The instruction requires these two output files to be left at /app. Beyond
# executing /app/recover.py (which proves the program generalizes), the
# verifier MUST also confirm the actual on-disk deliverables exist and carry
# the correct content for the visible /app/volume.bin input.
if [ -f /app/recovered.json ] && [ -f /app/evidence.json ] && [ -f /tests/expected.json ]; then
    # (a) /app/recovered.json must match the visible-case expected records.
    if ! python3 - /app/recovered.json /tests/expected.json >&2 <<'PY'
import json, sys
rec = json.load(open(sys.argv[1]))
want = json.load(open(sys.argv[2]))
ok = (rec.get('records') == want.get('records')
      and rec.get('status') == want.get('status'))
if not ok:
    print('  expected:', json.dumps(want), file=sys.stderr)
    print('  got:     ', json.dumps(rec), file=sys.stderr)
sys.exit(0 if ok else 1)
PY
    then
        fail "deliverable /app/recovered.json content mismatch"
        all_ok=0
    fi
    # (2) /app/evidence.json must hash the visible volume + expected records.
    if ! python3 - /app/volume.bin /app/evidence.json /tests/expected.json >&2 <<'PY'
import json, sys, hashlib
data = open(sys.argv[1], 'rb').read()
ev = json.load(open(sys.argv[2]))
want = json.load(open(sys.argv[3]))
exp_image = hashlib.sha256(data).hexdigest()
payloads = ''.join(r['text'] for r in want['records']).encode('utf-8')
exp_rec = hashlib.sha256(payloads).hexdigest()
ok = exp_image == ev.get('image_sha256') and exp_rec == ev.get('records_sha256')
if not ok:
    print('  want image=%s got=%s' % (exp_image, ev.get('image_sha256')), file=sys.stderr)
    print('  want recs =%s got=%s' % (exp_rec, ev.get('records_sha256')), file=sys.stderr)
sys.exit(0 if ok else 1)
PY
    then
        fail "deliverable /app/evidence.json content mismatch"
        all_ok=0
    fi
else
    fail "visible deliverables /app/recovered.json and /app/evidence.json not both present"
    all_ok=0
fi

[ "$all_ok" = 1 ] && reward=1
echo "$reward" > /logs/verifier/reward.txt
echo "indigo-archive verifier reward=$reward" >&2
exit 0
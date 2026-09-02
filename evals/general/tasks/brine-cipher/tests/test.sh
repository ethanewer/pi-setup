#!/bin/bash
# Brine Cipher verifier. Enforces the no-modify rule, checks the visible
# deliverables, and EXECUTES the deliverable tool /app/dewal.py on hidden
# envelopes, proving each decoded output is a genuine WAL accepted by SQLite.
# Writes reward to reward.txt.
set -u

mkdir -p /logs/verifier
reward=0
ok=1
fail() { echo "FAIL: $*" >&2; ok=0; }

PRISTINE_DB_SHA="a209ba85773882b79b8147779c406fbb67a12dcb723ba7c4ea7ca3168e651cc8"
PRISTINE_ENC_SHA="6c86e77bd74d7ac1c5fea68d3892f04f697d04a3695b835f442608771bc9323d"
VIS_MAX=2507
VIS_KEY=92

check_sha() { # path expected tag
    if [ ! -f "$1" ]; then
        fail "no-modify: $3 missing"
    else
        actual="$(sha256sum "$1" | awk '{print $1}')"
        [ "$actual" = "$2" ] || fail "no-modify: $3 was modified"
    fi
}
check_sha /app/gauge.db "$PRISTINE_DB_SHA" /app/gauge.db
check_sha /app/gauge.db-wal.enc "$PRISTINE_ENC_SHA" /app/gauge.db-wal.enc

[ -f /app/dewal.py ] || fail "missing deliverable /app/dewal.py"
[ -f /app/gauge.db-wal ] || fail "missing deliverable /app/gauge.db-wal"
[ -f /app/answer.txt ] || fail "missing deliverable /app/answer.txt"

# ---- visible: restored WAL is valid, accepted by SQLite, and yields the peak ----
python3 - <<'PY' || fail "visible WAL/answer check failed"
import shutil, sqlite3, tempfile, os

wal = open('/app/gauge.db-wal', 'rb').read()
assert wal[:4] in (b'\x37\x7f\x06\x82', b'\x37\x7f\x06\x83'), wal[:4].hex()
assert len(wal) > 100

work = tempfile.mkdtemp(prefix='brinevis-')
shutil.copy('/app/gauge.db', os.path.join(work, 'g.db'))
shutil.copy('/app/gauge.db-wal', os.path.join(work, 'g.db-wal'))
con = sqlite3.connect(os.path.join(work, 'g.db'))
assert con.execute('PRAGMA integrity_check').fetchone()[0] == 'ok', 'integrity'
rows = list(con.execute('SELECT id, level_mm FROM gauge_readings ORDER BY id'))
peak = max(r[1] for r in rows)
assert peak == 2507, ('visible peak', rows)
# the peak must genuinely come from the WAL: the main db alone has less
con2 = sqlite3.connect(os.path.join(work, 'g.db'))
PY
W=$(mktemp -d)
cp /app/gauge.db "$W/dbalone.db"
python3 - "$W/dbalone.db" <<'PY' || true
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
rows = list(con.execute("SELECT level_mm FROM gauge_readings"))
peak = max(r[0] for r in rows) if rows else -1
assert peak < 2507, "peak visible without the WAL?"
PY

# ---- visible: answer.txt ----
python3 - <<'PY' || fail "answer.txt invalid"
line = open('/app/answer.txt').read()
line = line.strip()
assert line == 'max_level=2507', repr(line)
print('answer.txt OK:', line)
PY

# ---- visible: re-run the deliverable on the visible envelope ----
if [ -f /app/dewal.py ]; then
    python3 /app/dewal.py /app/gauge.db-wal.enc "$W/rerun.wal" > "$W/rerun.out" 2>&1 \
        || fail "dewal.py failed on visible envelope"
    grep -q "^KEY=$VIS_KEY$" "$W/rerun.out" || fail "visible KEY wrong: $(cat "$W/rerun.out")"
    cmp -s "$W/rerun.wal" /app/gauge.db-wal || fail "rerun output != /app/gauge.db-wal"
fi

# ---- hidden envelopes: execute the deliverable, prove SQLite accepts output ----
python3 - <<'PY' || fail "hidden cases failed"
import hashlib, json, os, shutil, sqlite3, subprocess, sys, tempfile

meta = json.load(open('/tests/hidden/expected.json'))
HIDDEN = '/tests/hidden'
failed = []
cases = sorted(k for k in meta.keys())
if not cases:
    failed.append('no hidden cases')
for case in cases:
    base = os.path.join(HIDDEN, case)
    enc = os.path.join(base, 'gauge.db-wal.enc')
    db = os.path.join(base, 'gauge.db')
    if not (os.path.isfile(enc) and os.path.isfile(db)):
        failed.append('%s: malformed case' % case)
        continue
    exp_key = int(meta[case]['expected_key'])
    exp_max = int(meta[case]['expected_max'])
    exp_sha = meta[case]['expected_wal_sha256']
    work = tempfile.mkdtemp(prefix='brineverify-')
    try:
        out = os.path.join(work, 'out.wal')
        r = subprocess.run([sys.executable, '/app/dewal.py', enc, out],
                           capture_output=True, text=True, timeout=120)
        if r.returncode != 0:
            failed.append('%s: dewal.py exited %d' % (case, r.returncode))
            continue
        key_line = [l for l in r.stdout.splitlines() if l.startswith('KEY=')]
        if not key_line or key_line[0] != 'KEY=%d' % exp_key:
            failed.append('%s: KEY line %r' % (case, r.stdout))
            continue
        wal = open(out, 'rb').read()
        if wal[:4] not in (b'\x37\x7f\x06\x82', b'\x37\x7f\x06\x83'):
            failed.append('%s: bad magic %s' % (case, wal[:4].hex()))
            continue
        if hashlib.sha256(wal).hexdigest() != exp_sha:
            failed.append('%s: decoded WAL sha mismatch' % case)
            continue
        # prove SQLite accepts the decoded WAL against the case database
        shutil.copy(db, os.path.join(work, 'g.db'))
        shutil.copy(out, os.path.join(work, 'g.db-wal'))
        con = sqlite3.connect(os.path.join(work, 'g.db'))
        if con.execute('PRAGMA integrity_check').fetchone()[0] != 'ok':
            failed.append('%s: integrity_check not ok' % case)
            continue
        peak = max(r[0] for r in con.execute('SELECT level_mm FROM gauge_readings'))
        if peak != exp_max:
            failed.append('%s: peak %d != %d' % (case, peak, exp_max))
    finally:
        shutil.rmtree(work, ignore_errors=True)

if failed:
    print('hidden failures:', failed)
    raise SystemExit(1)
print('all hidden cases OK')
PY

rm -rf "$W"

[ "$ok" -eq 1 ] && reward=1
echo "$reward" > /logs/verifier/reward.txt
echo "reward=$reward" >&2
exit 0

#!/bin/bash
# Hollow Ledge verifier. Runs as root after the agent finishes; /tests is
# mounted read-only. Executes the deliverable /app/decode.c on the visible and
# hidden inputs and checks every deliverable. Writes reward to reward.txt.
set -u
mkdir -p /logs/verifier
reward=0
ok=1
fail() { echo "FAIL: $*" >&2; ok=0; }

HIDDEN=/tests/hidden
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/decode"

# ---------------------------------------------------------------------------
# 0) compile the deliverable; check deliverables + restored state exist
# ---------------------------------------------------------------------------
gcc -O2 -o "$BIN" /app/decode.c 2>/dev/null || fail "decode.c did not compile"
for f in /app/decode.c /app/creds.txt /app/key.pem; do
  [ -e "$f" ] || fail "missing deliverable $f"
done
# The restored valid WAL must be present with the native magic (checked BEFORE
# any sqlite connection, since sqlite may checkpoint-merge and reclaim it).
[ -f /app/ledge.db-wal ] || fail "no restored /app/ledge.db-wal"
magic=$(od -An -tx1 -N4 /app/ledge.db-wal | tr -d ' \n')
[ "$magic" = "377f0682" ] || fail "/app/ledge.db-wal has wrong magic"
[ -f /app/recovered/privkey.pem ] && [ -f /app/recovered/cert.pem ] || fail "no carve output in /app/recovered"
[ "$(find /app/recovered -type f | wc -l)" -eq 2 ] || fail "recovered dir has extra files"

# ---------------------------------------------------------------------------
# 1) unwal on the visible /app obf -> valid magic; isolated DB proves the rows
# ---------------------------------------------------------------------------
"$BIN" unwal /app/ledge.db-wal.obf "$WORK/visible.wal" >/dev/null 2>&1 || fail "unwal on main obf failed"
python3 - "$WORK/visible.wal" /tests/expected.json <<'PY' || fail "visible unwal/cfg check failed"
import sys, sqlite3, json, os
wal = open(sys.argv[1], 'rb').read()
assert len(wal) > 100
assert wal[:4] == b'\x37\x7f\x06\x82', ("magic mismatch", wal[:4].hex())
exp = json.load(open(sys.argv[2]))
# isced copy of the shipped main DB plus the decoded WAL -> cfg rows
import shutil
shutil.copy('/app/ledge.db', '/tmp/_isolated.db')
shutil.copy(sys.argv[1], '/tmp/_isolated.db-wal')
con = sqlite3.connect('/tmp/_isolated.db')
cfg = {k: v for k, v in con.execute('SELECT key, value FROM cfg')}
assert sorted(cfg.keys()) == sorted(exp['cfg_keys']), ("cfg keys", sorted(cfg.keys()))
assert cfg['username'].decode() == exp['username']
assert cfg['endpoint'].decode() == exp['endpoint']
assert cfg['passhash'].hex() == exp['passhash_hex'], ("passhash", cfg['passhash'].hex())
assert cfg['salt'].hex() == exp['salt_hex'], ("salt", cfg['salt'].hex())
assert cfg['kind'].decode() == exp['kind']
os.remove('/tmp/_isolated.db'); os.remove('/tmp/_isolated.db-wal')
print("visible decode + cfg OK")
PY

# ---------------------------------------------------------------------------
# 2) unwal on a HIDDEN wal (different key byte + different content)
# ---------------------------------------------------------------------------
"$BIN" unwal "$HIDDEN/g1_wal.bin" "$WORK/h1.wal" >"$WORK/h1.out" 2>&1 || fail "unwal on hidden g1 failed"
grep -q "^KEY=" "$WORK/h1.out" || fail "hidden g1 did not report a KEY"
python3 - "$WORK/h1.wal" <<'PY' || fail "hidden g1 decode invalid"
import sys
b = open(sys.argv[1], 'rb').read()
assert b[:4] == bytes([0x37, 0x7f, 0x06, 0x82]), "hidden wal magic mismatch"
assert len(b) > 100, "hidden wal too short"
print("hidden g1 unwal OK len=%d" % len(b))
PY
cmp -s "$WORK/h1.wal" "$WORK/visible.wal" && fail "hidden wal equals visible wal" || true

# ---------------------------------------------------------------------------
# 3) carve on the visible carrier: /app/recovered == ground truth from carrier
# ---------------------------------------------------------------------------
rm -rf "$WORK/recarve"; mkdir -p "$WORK/recarve"
"$BIN" carve /app/carrier.bin "$WORK/recarve" >/dev/null 2>&1 || fail "carve visible rerun failed"
python3 - "$WORK/recarve" /app/recovered <<'PY' || fail "carve visible mismatch"
import struct, sys
car = open('/app/carrier.bin', 'rb').read()
i = car.index(b'LVPR'); lpriv = struct.unpack('<I', car[i+4:i+8])[0]
priv = car[i+8:i+8+lpriv]
j = car.index(b'LVCR', i); lcert = struct.unpack('<I', car[j+4:j+8])[0]
cert = car[j+8:j+8+lcert]
recpriv = open(sys.argv[1]+'/privkey.pem', 'rb').read()
reccert = open(sys.argv[1]+'/cert.pem', 'rb').read()
assert recpriv == priv, "rerun carve privkey != ground truth"
assert reccert == cert, "rerun carve cert != ground truth"
ai = open(sys.argv[2]+'/privkey.pem', 'rb').read()
ac = open(sys.argv[2]+'/cert.pem', 'rb').read()
assert ai == priv, "agent recovered privkey != ground truth"
assert ac == cert, "agent recovered cert != ground truth"
print("carve visible OK priv=%d cert=%d" % (lpriv, lcert))
PY

# ---------------------------------------------------------------------------
# 4) carve on a HIDDEN carrier (different key/cert/offset): byte compare
# ---------------------------------------------------------------------------
rm -rf "$WORK/h2carve"; mkdir -p "$WORK/h2carve"
"$BIN" carve "$HIDDEN/g2_carrier.bin" "$WORK/h2carve" >/dev/null 2>&1 || fail "carve on hidden g2 failed"
cmp -s "$WORK/h2carve/privkey.pem" "$HIDDEN/expected_priv_g2.pem" || fail "hidden carve privkey mismatch"
cmp -s "$WORK/h2carve/cert.pem"     "$HIDDEN/expected_cert_g2.pem" || fail "hidden carve cert mismatch"

# ---------------------------------------------------------------------------
# 5) key.pem == privkey bytes then cert bytes (no separator)
# ---------------------------------------------------------------------------
cat /app/recovered/privkey.pem /app/recovered/cert.pem > "$WORK/expected_key.pem"
cmp -s "$WORK/expected_key.pem" /app/key.pem || fail "key.pem != privkey then cert"

# ---------------------------------------------------------------------------
# 6) creds.txt: user == real user; password reverses the check (recompile+run)
# ---------------------------------------------------------------------------
python3 - "$WORK" <<'PY' || fail "creds/check reversal failed"
import sys, sqlite3, subprocess
WORK = sys.argv[1]
username = password = None
for line in open('/app/creds.txt'):
    line = line.rstrip('\n')
    if line.startswith('username='):
        username = line[len('username='):]
    elif line.startswith('password='):
        password = line[len('password='):]
assert username and password, "creds.txt missing lines"
con = sqlite3.connect('/app/ledge.db')
cfg = {k: v for k, v in con.execute('SELECT key, value FROM cfg')}
assert username == cfg['username'].decode(), ('username mismatch', username)
assert len(password) == 12, ('password len', len(password))
for ch in password:
    assert 0x20 <= ord(ch) <= 0x7e, "password not printable"

def f(x): return ((x * 0x35 + 0x2f) ^ 0xa5) & 0xff
if bytes(f(ord(c)) for c in password) != cfg['passhash']:
    raise SystemExit('password does not reproduce the stored passhash')

r = subprocess.run(['gcc', '-O2', '-o', WORK+'/re_check', '/app/src/check.c'],
                   capture_output=True)
assert r.returncode == 0, 'recompile of check.c failed'
r1 = subprocess.run([WORK+'/re_check', password], capture_output=True, text=True)
assert r1.returncode == 0 and r1.stdout.strip() == 'ACCEPT', ('recompiled check', r1.stdout)
r2 = subprocess.run(['/usr/local/bin/ledgecheck', password], capture_output=True, text=True)
assert r2.returncode == 0 and r2.stdout.strip() == 'ACCEPT', ('prebuilt check', r2.stdout)
print('creds OK username=%s password=%s' % (username, password))
PY

[ "$ok" -eq 1 ] && reward=1
echo "$reward" > /logs/verifier/reward.txt
echo "reward=$reward" >&2
exit 0
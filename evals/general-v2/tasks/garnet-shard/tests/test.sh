#!/bin/bash
# garnet-shard verifier. Builds /app/gullbreak.c (binary + shared object),
# runs the deliverable on the visible and every hidden scenario, checks the
# recovered 32-bit subkey via the recover_gull_key calling convention, the
# decrypted plaintext, the delivered binary, and the creds.txt summary.
set -u
mkdir -p /logs/verifier
REWARD=0
LOG(){ echo "$*"; }
FAIL=0

PRISTINE_PAIRS_SHA="$(sha256sum /app/artifacts/pairs.txt 2>/dev/null | awk '{print $1}')"
PRISTINE_TARGET_SHA="$(sha256sum /app/artifacts/target.hex 2>/dev/null | awk '{print $1}')"

[ -f /app/gullbreak.c ] || { LOG "DELIVERABLE /app/gullbreak.c missing"; echo 0 > /logs/verifier/reward.txt; exit 0; }

# compile fresh from the delivered source (failed build must fail the reward)
rm -f /tmp/gullbreak /tmp/gullbreak.so /tmp/gccerr
gcc -O2 -o /tmp/gullbreak /app/gullbreak.c 2>/tmp/gccerr || echo nok >> /tmp/gccerr
gcc -O2 -shared -fPIC -o /tmp/gullbreak.so /app/gullbreak.c 2>>/tmp/gccerr || echo nok >> /tmp/gccerr
if [ ! -x /tmp/gullbreak ] || [ ! -f /tmp/gullbreak.so ]; then
  LOG "gullbreak.c failed to compile: $(head -c 300 /tmp/gccerr)"
  echo 0 > /logs/verifier/reward.txt
  exit 0
fi

# no-modify guard on the supplied artifacts
cur="$(sha256sum /app/artifacts/pairs.txt 2>/dev/null | awk '{print $1}')"
[ "$cur" = "$PRISTINE_PAIRS_SHA" ] || { LOG "pairs.txt was modified"; FAIL=1; }
cur="$(sha256sum /app/artifacts/target.hex 2>/dev/null | awk '{print $1}')"
[ "$cur" = "$PRISTINE_TARGET_SHA" ] || { LOG "target.hex was modified"; FAIL=1; }

python3 - <<'PY'
import ctypes, json, os, subprocess, sys

failures = []

def cli_run(binary, pairs, target):
    try:
        r = subprocess.run([binary, pairs, target], capture_output=True,
                           text=True, timeout=120)
    except Exception as e:
        return None, None, "exec error %r" % e
    if r.returncode != 0:
        return None, None, "exit %d stderr=%s" % (r.returncode, r.stderr[:120])
    key = pl = None
    for ln in r.stdout.splitlines():
        if ln.startswith("key="):
            try: key = int(ln[4:], 10)
            except Exception: pass
        elif ln.startswith("plain="):
            pl = ln[6:].strip()
    return key, pl, None

def ctypes_key(so, pairs):
    lib = ctypes.CDLL(so)
    lib.recover_gull_key.restype = ctypes.c_uint32
    lib.recover_gull_key.argtypes = [ctypes.c_char_p]
    return lib.recover_gull_key(pairs.encode())

def check(label, pairs, target, exp):
    exp_key = exp["key"]
    malformed = exp.get("malformed_only", False)
    # calling convention first: unsigned 32-bit equality
    try:
        ck = ctypes_key("/tmp/gullbreak.so", pairs)
    except Exception as e:
        failures.append("%s: recover_gull_key driver error %r" % (label, e)); return
    if not isinstance(ck, int) or (ck & 0xFFFFFFFF) != exp_key:
        failures.append("%s: recover_gull_key returned %r != %d" % (label, ck, exp_key))
        return
    if malformed:
        print("%s: ctypes key=0 on malformed OK" % label)
        return
    key, pl, err = cli_run("/tmp/gullbreak", pairs, target)
    if err is not None:
        failures.append("%s: cli failed: %s" % (label, err)); return
    if key != exp_key:
        failures.append("%s: cli key %d != expected %d" % (label, key, exp_key))
    if pl is None or pl.lower() != exp["plain_hex"].lower():
        failures.append("%s: cli plain %r != expected %r" % (label, pl, exp["plain_hex"]))
    # the delivered binary must also work on the visible artifacts
    if label == "visible" and os.path.exists("/app/gullbreak") and os.access("/app/gullbreak", os.X_OK):
        k2, p2, e2 = cli_run("/app/gullbreak", pairs, target)
        if e2 is not None or k2 != exp_key or (p2 or "").lower() != exp["plain_hex"].lower():
            failures.append("%s: delivered /app/gullbreak binary misbehaves" % label)

# visible artifacts
if os.path.isfile("/app/artifacts/pairs.txt") and os.path.isfile("/app/artifacts/target.hex") \
   and os.path.isfile("/tests/expected.json"):
    try:
        exp = json.load(open("/tests/expected.json"))
        check("visible", "/app/artifacts/pairs.txt", "/app/artifacts/target.hex", exp)
    except Exception as e:
        failures.append("visible case error %r" % e)
else:
    failures.append("visible artifacts or /tests/expected.json missing")

# hidden scenarios
hdir = "/tests/hidden"
cases = sorted(os.listdir(hdir)) if os.path.isdir(hdir) else []
if not cases:
    failures.append("no hidden cases present")
for c in cases:
    base = os.path.join(hdir, c)
    pairs = os.path.join(base, "pairs.txt")
    target = os.path.join(base, "target.hex")
    expf = os.path.join(base, "expected.json")
    if not all(os.path.isfile(p) for p in (pairs, target, expf)):
        failures.append("hidden '%s' malformed fixture" % c); continue
    try:
        exp = json.load(open(expf))
        check("hidden-%s" % c, pairs, target, exp)
    except Exception as e:
        failures.append("hidden '%s' error %r" % (c, e))

# creds.txt deliverable must record the real recovered values
if os.path.isfile("/app/creds.txt"):
    try:
        lines = [l.strip() for l in open("/app/creds.txt") if l.strip()]
        want = json.load(open("/tests/expected.json"))
        ok = (len(lines) == 2 and lines[0] == "key=%d" % want["key"]
              and lines[1].startswith("plain=")
              and lines[1][6:].lower() == want["plain_hex"].lower())
        if not ok:
            failures.append("creds.txt wrong: %r" % lines)
    except Exception as e:
        failures.append("creds.txt unreadable %r" % e)
else:
    failures.append("missing /app/creds.txt")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -ne 0 ]; then FAIL=1; fi

if [ "$FAIL" -eq 0 ]; then
  REWARD=1
  LOG "ALL CHECKS PASS"
fi
echo "$REWARD" > /logs/verifier/reward.txt
exit 0

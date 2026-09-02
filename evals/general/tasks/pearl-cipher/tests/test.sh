#!/bin/bash
# Verifier for pearl-cipher: guards the provided cipher/key/target files,
# re-runs /app/crack.py on the visible and on hidden key/target pairs within a
# 90 s per-case budget, and verifies the recovered preimage with an EMBEDDED
# authoritative Pearl32 implementation. Writes 1 or 0 to reward.txt; every
# parse of agent output is guarded.
set -u

mkdir -p /logs/verifier
reward=0

fail() { echo "0" > /logs/verifier/reward.txt; echo "VERIFIER FAIL: $1"; exit 0; }

[ -f /app/crack.py ] || fail "missing /app/crack.py"

python3 - <<'PY'
import hashlib, json, os, re, subprocess, sys

fails = []
PRISTINE = {
    "/app/cipher.py":  "0445d3d64ea593a21dedb15f20cc65e3d15c22002b9956455fd123577ec2f708",
    "/app/key.txt":    "a167a236827fbafdc84c036bd4bc61c4ec8c07da74e9c751349938d1af608e2e",
    "/app/target.txt": "1f85673ddcc23708f8811f184af066ef61304b28778f58b94de865329892a4ef",
}

def sha(p):
    try:
        return hashlib.sha256(open(p, "rb").read()).hexdigest()
    except OSError:
        return None

# ---- embedded authoritative reference (not the agent's copy) ---------------
M32 = 0xFFFFFFFF

def round_key(K, i):
    z = (K ^ (0x9E3779B9 * i)) & M32
    z ^= z >> 16
    z = (z * 0x85EBCA6B) & M32
    z ^= z >> 13
    z = (z * 0xC2B2AE35) & M32
    z ^= z >> 16
    return z

def encrypt(x, K):
    L = (x >> 15) & 0x7FFF
    R = x & 0x7FFF
    for i in (1, 2, 3, 4):
        k = round_key(K, i)
        t = (R + k) & M32
        t ^= t >> 9
        t = (t * 0x045D9F3B) & M32
        t ^= t >> 11
        f = t & 0x7FFF
        L, R = R, L ^ f
    return (L << 15) | R

def read_hex(path):
    with open(path) as fh:
        return fh.read().strip()

def crack(key_hex, target_hex, out_json, budget=90):
    """Run the deliverable within budget; return (ok, detail)."""
    if os.path.exists(out_json):
        os.remove(out_json)
    try:
        r = subprocess.run([sys.executable, "/app/crack.py", key_hex, target_hex,
                            out_json], capture_output=True, text=True,
                           timeout=budget)
    except subprocess.TimeoutExpired:
        return False, "timeout after %ds (over budget)" % budget
    if r.returncode != 0:
        return False, "rc=%d %s" % (r.returncode, (r.stderr or "")[-200:])
    if not os.path.isfile(out_json):
        return False, "no output JSON written"
    try:
        with open(out_json) as fh:
            got = json.load(fh)
    except Exception as e:
        return False, "output JSON unparseable: %s" % e
    if not isinstance(got, dict) or "x" not in got or "y" not in got:
        return False, "output JSON lacks x/y: %r" % (got,)
    try:
        x = int(got["x"]); y = int(got["y"])
    except Exception:
        return False, "x/y not integers: %r" % (got,)
    T = int(target_hex, 16)
    K = int(key_hex, 16) & 0xFFFFFFFF
    if y != T:
        return False, "y=%d != target %d" % (y, T)
    if not (0 <= x < (1 << 30)):
        return False, "x=%d outside [0, 2^30)" % x
    if encrypt(x, K) != T:
        return False, "cipher check failed: encrypt(%d, K) != target" % x
    return True, "x=%d" % x

# ---- pristine-file guards --------------------------------------------------
for path, want in PRISTINE.items():
    if sha(path) != want:
        fails.append("%s modified or missing" % path)

# ---- visible case ----------------------------------------------------------
try:
    vk, vt = read_hex("/app/key.txt"), read_hex("/app/target.txt")
    int(vk, 16); int(vt, 16)
except Exception as e:
    fails.append("visible key/target unreadable: %s" % e)
    vk = vt = None
if vk:
    ok, detail = crack(vk, vt, "/tmp/pearl_visible.json")
    if not ok:
        fails.append("visible case: %s" % detail)
    try:
        want = json.load(open("/tests/expected_secret.json"))
        got = json.load(open("/app/secret.json"))
        if int(got.get("x", -1)) != int(want["x"]) or int(got.get("y", -1)) != int(want["y"]):
            fails.append("secret.json does not match visible expected")
    except Exception as e:
        fails.append("secret.json unreadable/wrong schema: %s" % e)

# ---- hidden cases ----------------------------------------------------------
hdir = "/tests/hidden"
cases = sorted(d for d in os.listdir(hdir)
               if os.path.isfile(os.path.join(hdir, d, "key.txt"))) \
        if os.path.isdir(hdir) else []
if len(cases) < 2:
    fails.append("expected >=2 hidden cases, found %d" % len(cases))
for c in cases:
    base = os.path.join(hdir, c)
    if not all(os.path.isfile(os.path.join(base, f)) for f in
               ("key.txt", "target.txt", "expected.json")):
        fails.append("hidden '%s' malformed" % c)
        continue
    hk, ht = read_hex(os.path.join(base, "key.txt")), read_hex(os.path.join(base, "target.txt"))
    ok, detail = crack(hk, ht, "/tmp/pearl_%s.json" % c)
    if not ok:
        fails.append("hidden '%s': %s" % (c, detail))

print("verify failures:", fails)
sys.exit(1 if fails else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0

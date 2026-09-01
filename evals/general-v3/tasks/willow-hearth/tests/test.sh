#!/bin/bash
# Verifier for willow-hearth. Compiles /app/decode.c, runs it on the visible
# and every hidden scenario, checks the recovered 32-bit subkey (via the
# recover_round_key calling convention), the decrypted plaintext, the
# combined key+cert PEM, and the credentials / archive passphrase.
set -u
mkdir -p /logs/verifier

# compile the deliverable (the failed build must fail the reward)
COMPILE_OK=1
gcc -O2 -shared -fPIC -o /tmp/decode.so /app/decode.c 2>/tmp/gccerr || COMPILE_OK=0
gcc -O2 -o /tmp/decode /app/decode.c 2>>/tmp/gccerr || COMPILE_OK=0
chmod +x /tmp/decode 2>/dev/null || true

python3 - /tmp/gccerr <<'PY'
import os, sys, json, subprocess, ctypes, zipfile, shutil

GCCERR = sys.argv[1]
failures = []
def fail(m): failures.append(m)

compiled = False
if os.path.exists("/tmp/decode") and os.path.exists("/tmp/decode.so"):
    compiled = True
else:
    e = open(GCCERR).read().strip()[:400]
    fail("decode.c failed to compile: %s" % e)

def parse_run(pairs, target):
    if not os.path.exists("/tmp/decode"):
        return None, None, None
    r = subprocess.run(["/tmp/decode", pairs, target],
                       capture_output=True, text=True, timeout=120)
    if r.returncode != 0:
        return None, None, r
    key = pl = None
    for ln in r.stdout.splitlines():
        if ln.startswith("key="):
            try: key = int(ln.split("=",1)[1]); 
            except Exception: pass
        elif ln.startswith("plain="):
            pl_x = ln.split("=",1)[1].strip()
            pl = pl_x
    return key, pl, r

def ctypes_key(pairs_path):
    lib = ctypes.CDLL("/tmp/decode.so")
    lib.recover_round_key.restype = ctypes.c_uint32
    lib.recover_round_key.argtypes = [ctypes.c_char_p]
    return lib.recover_round_key(ctypes.c_char_p(pairs_path.encode()))

def check_scenario(pairs, target, exp, label):
    key, pl, r = parse_run(pairs, target)
    if key is None or pl is None:
        fail("%s: decode binary unavailable or no key=/plain= (stderr: %s" % (
            label, (r.stdout if r else 'missing /tmp/decode')[:200]))
        return
    if key != exp["key"]:
        fail("%s: key %d != expected %d" % (label, key, exp["key"]))
    if pl.lower() != exp["plain_hex"].lower():
        fail("%s: plain %r != expected %r" % (label, pl, exp["plain_hex"]))
    # calling convention: the exported uint32 recovery function
    try:
        ck = ctypes_key(pairs)
    except Exception as e:
        fail("%s: recover_round_key driver error %r" % (label, e)); return
    if not isinstance(ck, int) or (ck & 0xFFFFFFFF) != exp["key"]:
        fail("%s: recover_round_key returned %r != %d" % (label, ck, exp["key"]))

# ---- visible ----
if compiled:
    if not os.path.exists("/app/artifacts/pairs.txt") or not os.path.exists("/app/artifacts/target.hex"):
        fail("visible artifacts missing")
    vis = {}
    if os.path.exists("/tests/expected.json"):
        vis = json.load(open("/tests/expected.json"))
    if os.path.exists("/app/artifacts/pairs.txt"):
        check_scenario("/app/artifacts/pairs.txt", "/app/artifacts/target.hex",
                       vis, "visible")

# ---- deliverables ----
if not os.path.exists("/app/decode.c"):
    fail("missing deliverable /app/decode.c")
if not os.path.exists("/app/key.pem"):
    fail("missing deliverable /app/key.pem")
else:
    # split the combined PEM; private key then certificate; public keys equal
    pem = open("/app/key.pem","r").read()
    keyblock = certblock = None
    if "BEGIN PRIVATE KEY" in pem:
        keyblock = pem[pem.index("-----BEGIN PRIVATE KEY"):pem.index("-----END PRIVATE KEY-----")+len("-----END PRIVATE KEY-----")]
        certb = pem
        if "BEGIN CERTIFICATE" in pem:
            cb = "-----BEGIN CERTIFICATE-----"; ce = "-----END CERTIFICATE-----"
            certblock = pem[pem.index(cb):pem.index(ce)+len(ce)]
    else:
        fail("key.pem missing an RSA/private-key PEM block")
    if keyblock and certblock:
        open("/tmp/k.pem","w").write(keyblock)
        open("/tmp/c.pem","w").write(certblock)
        # compare public keys
        k = subprocess.run(["openssl","pkey","-in","/tmp/k.pem","-pubout","-outform","PEM"], capture_output=True)
        c = subprocess.run(["openssl","x509","-in","/tmp/c.pem","-pubkey","-noout"], capture_output=True)
        try:
            kpub = k.stdout
            cpub = c.stdout
            if kpub != cpub:
                fail("key.pem certificate public key != private key public key")
        except Exception as e:
            fail("key.pem pub key compare error %r" % (e,))
    else:
        fail("key.pem blocks not parsed (private + certificate)")

# creds.txt
if os.path.exists("/app/creds.txt"):
    creds = {}
    for ln in open("/app/creds.txt"):
        if "=" in ln:
            k_,_,v = ln.partition("="); creds[k_.strip()] = v.strip()
    wantkey = vis.get("key", None)
    if wantkey is not None:
        if creds.get("subkey") is None or int(creds["subkey"]) != wantkey:
            fail("creds.txt subkey %r != expected %d" % (creds.get("subkey"), wantkey))
    # passphrase opens the archive
    if os.path.exists("/app/artifacts/secrets.zip") and creds.get("passphrase"):
        try:
            z = zipfile.ZipFile("/app/artifacts/secrets.zip")
            z.setpassword(creds["passphrase"].encode())
            names = z.namelist()
            data = z.open("secret.txt").read()
            if not data:
                fail("secret.txt empty")
        except Exception as e:
            fail("creds.txt passphrase did not open archive: %r" % (e,))
    # record equals ascii of the decrypted plain
    if vis.get("plain_hex") and creds.get("record") is not None:
        try:
            rec = bytes.fromhex(vis["plain_hex"]).decode("latin1")
            if creds["record"] != rec:
                fail("creds.txt record %r != recovered %r" % (creds.get("record"), rec))
        except Exception as e:
            fail("creds record check error %r" % (e,))
else:
    fail("missing deliverable /app/creds.txt")

# ---- hidden cases ----
hroot = "/tests/hidden"
hid = []
if os.path.isdir(hroot):
    hid = sorted(d for d in os.listdir(hroot)
                 if os.path.isdir(os.path.join(hroot, d)))
if len(hid) < 2:
    fail("expected >= 2 hidden cases, found %d" % len(hid))
for name in hid:
    d = os.path.join(hroot, name)
    ep = os.path.join(d, "expected.json")
    if not (os.path.exists(os.path.join(d,"pairs.txt")) and os.path.exists(ep) and os.path.exists(os.path.join(d,"target.hex"))):
        fail("%s incomplete hidden case" % name); continue
    exp = json.load(open(ep))
    check_scenario(os.path.join(d,"pairs.txt"), os.path.join(d,"target.hex"), exp, "hidden:"+name)

if failures:
    print("FAILURES")
    for m in failures: print(" - "+m)
    open("/logs/verifier/reward.txt","w").write("0")
    sys.exit(0)
open("/logs/verifier/reward.txt","w").write("1")
print("ALL PASS")
sys.exit(0)
PY
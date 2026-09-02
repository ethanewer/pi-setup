#!/bin/bash
# Verifier for cobalt-quill. Compiles /app/keyfind.c as a shared object (to call
# the required uint32_t recover_key(const char *) entry point via ctypes) and as
# the CLI binary, then runs both on the visible artifacts and on every hidden
# fixture (different keys incl. top-bit-set, malformed pairs). Writes REWARD
# (0/1) to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
reward=0

COMPILE_OK=1
gcc -O2 -shared -fPIC -o /tmp/keyfind.so /app/keyfind.c 2>/tmp/gccerr || COMPILE_OK=0
gcc -O2 -o /tmp/keyfind /app/keyfind.c 2>>/tmp/gccerr || COMPILE_OK=0
chmod +x /tmp/keyfind 2>/dev/null || true

python3 - <<'PY'
import ctypes
import json
import os
import subprocess
import sys

failures = []
compiled = os.path.exists("/tmp/keyfind.so") and os.path.exists("/tmp/keyfind")
if not compiled:
    err = ""
    try:
        with open("/tmp/gccerr") as fh:
            err = fh.read().strip()[:400]
    except OSError:
        pass
    failures.append("keyfind.c failed to compile: %s" % err)


def drv_key(pairs_path):
    lib = ctypes.CDLL("/tmp/keyfind.so")
    lib.recover_key.restype = ctypes.c_uint32
    lib.recover_key.argtypes = [ctypes.c_char_p]
    return lib.recover_key(pairs_path.encode())


def cli_run(pairs, target):
    r = subprocess.run(["/tmp/keyfind", pairs, target],
                       capture_output=True, text=True, timeout=120)
    key = pl = None
    if r.returncode == 0:
        for ln in r.stdout.splitlines():
            if ln.startswith("key="):
                try:
                    key = int(ln.split("=", 1)[1])
                except Exception:
                    key = None
            elif ln.startswith("plain="):
                pl = ln.split("=", 1)[1].strip().lower()
    return key, pl, r


def check_case(pairs, target, exp, label):
    # calling convention: recover_key must return the exact unsigned 32-bit key
    try:
        ck = drv_key(pairs)
    except Exception as e:
        failures.append("%s: recover_key driver error %r" % (label, e))
        return
    want = int(exp["key"]) & 0xFFFFFFFF
    if not isinstance(ck, int) or (ck & 0xFFFFFFFF) != want:
        failures.append("%s: recover_key returned %r != %d" % (label, ck, want))
        return
    if target is None:
        return
    key, pl, r = cli_run(pairs, target)
    if key is None or pl is None:
        failures.append("%s: CLI failed (rc=%s, stderr=%r)" % (
            label, getattr(r, "returncode", "?"), getattr(r, "stderr", "")[:200]))
        return
    if key != want:
        failures.append("%s: CLI key %d != %d" % (label, key, want))
    if pl.lower() != str(exp["plain_hex"]).lower():
        failures.append("%s: CLI plain %r != %r" % (label, pl, exp["plain_hex"]))


if compiled:
    # visible artifacts
    if not (os.path.isfile("/app/artifacts/pairs.txt") and os.path.isfile("/app/artifacts/target.hex")):
        failures.append("visible artifacts missing")
    else:
        try:
            with open("/tests/expected.json") as fh:
                vis = json.load(fh)
        except Exception:
            vis = None
            failures.append("visible expected.json unreadable")
        if vis:
            check_case("/app/artifacts/pairs.txt", "/app/artifacts/target.hex", vis, "visible")
        # creds.txt deliverable
        try:
            with open("/app/creds.txt") as fh:
                got = {}
                for ln in fh.read().splitlines():
                    if "=" in ln:
                        k, v = ln.split("=", 1)
                        got[k.strip()] = v.strip()
        except Exception:
            got = None
            failures.append("creds.txt unreadable")
        if got is not None:
            if got.get("subkey") != str(vis["key"]):
                failures.append("creds.txt subkey %r != %r" % (got.get("subkey"), str(vis["key"])))
            if got.get("record", "").rstrip() != str(vis["record"]).rstrip():
                failures.append("creds.txt record %r != %r" % (got.get("record"), vis["record"]))

    # hidden fixtures
    hidden = "/tests/hidden"
    if os.path.isdir(hidden):
        cases = sorted(d for d in os.listdir(hidden) if os.path.isdir(os.path.join(hidden, d)))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden, c)
            try:
                with open(os.path.join(base, "expected.json")) as fh:
                    exp = json.load(fh)
            except Exception:
                failures.append("hidden '%s': unreadable expected.json" % c)
                continue
            pairs = os.path.join(base, "pairs.txt")
            if not os.path.isfile(pairs):
                failures.append("hidden '%s': pairs.txt missing" % c)
                continue
            target = os.path.join(base, "target.hex")
            if os.path.isfile(target):
                check_case(pairs, target, exp, c)
            else:
                check_case(pairs, None, exp, c)
    else:
        failures.append("hidden cases directory missing")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0

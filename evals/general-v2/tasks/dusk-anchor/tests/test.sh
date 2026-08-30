#!/bin/bash
# Verifier for dusk-anchor: checks the standalone-clone contract for the
# vellum transform. Rebuilds the agent's clone in a clean scratch directory
# (only app.c + Makefile), confirms static linkage and isolation, EXECUTES the
# deliverable binary on hidden inputs against an independently derived
# reference of the spec, and re-checks /app/proof.txt. Writes REWARD (0/1) to
# /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
reward=0

python3 - <<'PY'
import hashlib, json, os, shutil, subprocess, sys, tempfile

APP_C = "/app/dusk/app.c"
MAKEFILE = "/app/dusk/Makefile"
BINARY = "/app/dusk/app"
PROOF = "/app/proof.txt"
SEED = "/app/seed.bin"
HIDDEN = "/tests/hidden"

failures = []


def ref_vellum(data: bytes) -> bytes:
    """Independent reference implementation of the documented transform."""
    r = bytes(reversed(data))
    k = 0x5D
    out = bytearray()
    for b in r:
        o = b ^ k
        out.append(o)
        k = (k + o + 0x33) & 0xFF
    t = 0
    for o in out:
        t ^= o
    out.append(t)
    return bytes(out)


def run_binary(exe, stdin_path):
    with open(stdin_path, "rb") as fh:
        r = subprocess.run([exe], stdin=fh, capture_output=True, timeout=120)
    return r


# --- deliverables present -------------------------------------------------
for p in (APP_C, MAKEFILE, BINARY, PROOF):
    if not os.path.isfile(p):
        failures.append("missing deliverable %s" % p)
if SEED and not os.path.isfile(SEED):
    failures.append("fixture /app/seed.bin missing")

# --- source isolation: stdlib-only includes, no /app or fixture references -
if os.path.isfile(APP_C):
    src = open(APP_C, errors="replace").read()
    if '#include "' in src:
        failures.append("app.c uses a local quoted include")
    for bad in ("/app", "vellum", "seed.bin", "tests/"):
        if bad in src:
            failures.append("app.c references forbidden token %r" % bad)
    import re
    incs = re.findall(r'^\s*#\s*include\s*([<"][^>"]+[>"])', src, re.M)
    allowed = {"stdio.h", "stdlib.h", "string.h", "stdint.h",
               "stddef.h", "unistd.h", "limits.h", "errno.h",
               "stdbool.h"}
    for inc in incs:
        if not (inc.startswith("<") and inc[1:-1] in allowed):
            failures.append("app.c includes non-stdlib header %s" % inc)

# --- clean-room rebuild ----------------------------------------------------
scratch_ok = False
scratch_bin = None
if os.path.isfile(APP_C) and os.path.isfile(MAKEFILE):
    tmp = tempfile.mkdtemp(prefix="dusk-clean-")
    try:
        shutil.copy(APP_C, os.path.join(tmp, "app.c"))
        shutil.copy(MAKEFILE, os.path.join(tmp, "Makefile"))
        r = subprocess.run(["make", "-C", tmp], capture_output=True,
                           text=True, timeout=180)
        if r.returncode != 0:
            failures.append("clean-room make failed: %s" % r.stderr[-400:])
        else:
            cand = os.path.join(tmp, "app")
            if not os.path.isfile(cand):
                failures.append("clean-room make produced no ./app")
            else:
                fr = subprocess.run(["file", "-b", cand], capture_output=True,
                                    text=True, timeout=60)
                dr = subprocess.run(["ldd", cand], capture_output=True,
                                    text=True, timeout=60)
                static_ok = ("statically linked" in fr.stdout
                             or "not a dynamic executable" in dr.stdout
                             or (dr.returncode != 0 and "static" in fr.stdout))
                if not static_ok:
                    failures.append("clean-room app is not statically linked")
                else:
                    scratch_ok = True
                    scratch_bin = cand
    finally:
        pass  # keep the scratch dir for debugging on failure

if not scratch_ok:
    failures.append("clean-room build unavailable")

# --- deliverable + clean-room binary vs hidden cases (reference-derived) ---
hidden = sorted(d for d in os.listdir(HIDDEN)) if os.path.isdir(HIDDEN) else []
if not hidden:
    failures.append("no hidden cases present")
for case in hidden:
    base = os.path.join(HIDDEN, case)
    inp = os.path.join(base, "input.bin")
    exp = os.path.join(base, "expected.json")
    if not (os.path.isfile(inp) and os.path.isfile(exp)):
        failures.append("hidden case '%s' malformed" % case)
        continue
    data = open(inp, "rb").read()
    want = ref_vellum(data)
    try:
        meta = json.load(open(exp))
        if meta.get("sha256") != hashlib.sha256(want).hexdigest():
            failures.append("hidden '%s': expected.json disagrees with "
                            "reference (fixture bug)" % case)
    except Exception as e:
        failures.append("hidden '%s': unreadable expected.json (%s)" % (case, e))

    for label, exe in (("deliverable", BINARY), ("clean-room", scratch_bin)):
        if exe is None or not os.path.isfile(exe):
            failures.append("hidden '%s': cannot run %s binary" % (case, label))
            continue
        try:
            r = run_binary(exe, inp)
        except Exception as e:
            failures.append("hidden '%s' (%s): run crashed (%s)" % (case, label, e))
            continue
        if r.returncode != 0:
            failures.append("hidden '%s' (%s): exit %d" % (case, label, r.returncode))
        elif r.stdout != want:
            failures.append("hidden '%s' (%s): output mismatch" % (case, label))

# --- proof digest ----------------------------------------------------------
if os.path.isfile(PROOF) and os.path.isfile(BINARY) and os.path.isfile(SEED):
    try:
        r = run_binary(BINARY, SEED)
        digest = hashlib.sha256(r.stdout).hexdigest()
        got = open(PROOF).read().strip().lower()
        if r.returncode != 0:
            failures.append("proof run exited %d" % r.returncode)
        elif got != digest:
            failures.append("proof.txt mismatch (got %s, want %s)" % (got, digest))
    except Exception as e:
        failures.append("proof re-run failed: %s" % e)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0

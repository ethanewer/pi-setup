#!/bin/bash
# Verifier for sable-hook: cross-checks the recovered passphrase against the
# real gatekeeper binary, verifies the target application is pristine and
# still rejects wrong secrets, deletes the side-effect file and EXECUTES the
# deliverable runner (/app/unseal.py) so the app must genuinely produce it,
# then replays hidden probe cases in /tests/hidden.
# Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the target application (agent must not modify it).
PRISTINE_SVC_SHA="0f1cad73508669b54c7420e776988aef104efbe9b3e3ae7dbf8cf7da67721cf4"

svc_ok=1
if [ ! -f /app/vault_service.py ]; then
    echo "no-modify: /app/vault_service.py missing" >&2
    svc_ok=0
else
    actual="$(sha256sum /app/vault_service.py | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_SVC_SHA" ]; then
        echo "no-modify: /app/vault_service.py was modified" >&2
        svc_ok=0
    fi
fi

python3 - "$svc_ok" <<'PY'
import hashlib
import importlib
import json
import os
import shutil
import subprocess
import sys
import tempfile

SVC_OK = int(sys.argv[1])

GK = "/app/gatekeeper"
SVC = "/app/vault_service.py"
RUN = "/app/unseal.py"
PW_FILE = "/app/recovered_passphrase.txt"
OUT_DIR = "/app/vault_out"
OUT_FILE = "/app/vault_out/unsealed.txt"

failures = []
if SVC_OK != 1:
    failures.append("vault_service.py missing or modified (no-modify rule)")

if not os.path.isfile(GK):
    failures.append("missing /app/gatekeeper")


def body_from_service(svc):
    """The exact body the PRISTINE application writes when unsealed."""
    return "UNSEALED by vault_service\nsecret_ok=1\nnonce=%s\n" % svc.UNSEAL_NONCE


def run_runner():
    return subprocess.run([sys.executable, RUN], cwd="/app",
                          capture_output=True, text=True, timeout=120)


# service module import (file is sha-pinned pristine, so import is safe)
svc = None
if SVC_OK == 1 and os.path.isfile(GK):
    try:
        sys.path.insert(0, "/app")
        svc = importlib.import_module("vault_service")
    except Exception as exc:
        failures.append("cannot import vault_service: %r" % exc)

correct_secret = None

if svc is not None and os.path.isfile(GK) and os.path.isfile(PW_FILE):
    # --- deliverable 1: recovered passphrase must validate on the binary ---
    try:
        with open(PW_FILE, encoding="utf-8") as fh:
            pw = fh.read().strip()
        r = subprocess.run([GK, pw], capture_output=True, text=True, timeout=60)
        line = (r.stdout or "").strip()
        if r.returncode != 0 or not line.startswith("GRANTED DEPLOY_SECRET="):
            failures.append("gatekeeper rejects /app/recovered_passphrase.txt")
        else:
            correct_secret = line.split("=", 1)[1].strip()
            if hashlib.sha256(correct_secret.encode()).hexdigest() != svc.VAULT_DIGEST:
                failures.append("derived secret not accepted by vault_service")
    except Exception as exc:
        failures.append("passphrase check crashed: %r" % exc)

    # --- gatekeeper still locks wrong input (binary not neutered) ---
    try:
        r = subprocess.run([GK, "definitely-wrong-guess"], capture_output=True,
                           text=True, timeout=60)
        if "LOCKED" not in (r.stdout or "") or "GRANTED" in (r.stdout or ""):
            failures.append("gatekeeper no longer locks wrong passphrases")
    except Exception as exc:
        failures.append("gatekeeper negative check crashed: %r" % exc)

    # --- application still rejects a wrong secret ---
    try:
        shutil.rmtree(OUT_DIR, ignore_errors=True)
        if svc.open_vault("vault-open-wrong-secret!!") is not False:
            failures.append("vault_service accepts a wrong secret")
        if os.path.exists(OUT_FILE):
            failures.append("side-effect file appeared for a wrong secret")
    except Exception as exc:
        failures.append("negative vault check crashed: %r" % exc)

    # --- deliverables 2+3: EXECUTE the runner, app must produce the file ---
    if correct_secret is not None:
        if not os.path.isfile(RUN):
            failures.append("missing /app/unseal.py")
        else:
            try:
                expected_body = body_from_service(svc)
                shutil.rmtree(OUT_DIR, ignore_errors=True)
                r = run_runner()
                if r.returncode != 0:
                    failures.append("unseal.py exited %d" % r.returncode)
                if not os.path.isfile(OUT_FILE):
                    failures.append("unseal.py run produced no side-effect file")
                else:
                    with open(OUT_FILE, encoding="utf-8") as fh:
                        got = fh.read()
                    if got != expected_body:
                        failures.append("side-effect file is not the app's "
                                        "genuine output (fabricated?)")
                    # reference run of the pristine app must agree exactly
                    shutil.rmtree(OUT_DIR, ignore_errors=True)
                    if svc.open_vault(correct_secret) is not True:
                        failures.append("pristine app rejected derived secret")
                    with open(OUT_FILE, encoding="utf-8") as fh:
                        ref = fh.read()
                    if ref != expected_body:
                        failures.append("pristine app body mismatch")
            except Exception as exc:
                failures.append("runner execution crashed: %r" % exc)
    else:
        failures.append("no derived secret; cannot validate runner")

    # --- hidden probe cases in /tests/hidden ---
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(d for d in os.listdir(hidden_dir)
                       if os.path.isdir(os.path.join(hidden_dir, d)))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            meta_path = os.path.join(hidden_dir, c, "expected.json")
            try:
                with open(meta_path, encoding="utf-8") as fh:
                    meta = json.load(fh)
            except Exception:
                failures.append("hidden '%s' unreadable meta" % c)
                continue
            kind = meta.get("kind")
            try:
                if kind == "standalone":
                    # runner must be self-sufficient without the passphrase file
                    tmpd = tempfile.mkdtemp()
                    stash = os.path.join(tmpd, "pw.stash")
                    had_pw = os.path.isfile(PW_FILE)
                    if had_pw:
                        shutil.move(PW_FILE, stash)
                    try:
                        shutil.rmtree(OUT_DIR, ignore_errors=True)
                        r = run_runner()
                        ok = (r.returncode == 0 and os.path.isfile(OUT_FILE))
                        if ok:
                            with open(OUT_FILE, encoding="utf-8") as fh:
                                ok = fh.read() == body_from_service(svc)
                        if not ok:
                            failures.append("hidden '%s': runner not "
                                            "self-sufficient" % c)
                    finally:
                        if had_pw:
                            shutil.move(stash, PW_FILE)
                        shutil.rmtree(tmpd, ignore_errors=True)
                elif kind == "fresh_dir":
                    # runner must work when the output dir does not exist
                    shutil.rmtree(OUT_DIR, ignore_errors=True)
                    r = run_runner()
                    ok = (r.returncode == 0 and os.path.isfile(OUT_FILE))
                    if ok:
                        with open(OUT_FILE, encoding="utf-8") as fh:
                            ok = fh.read() == body_from_service(svc)
                    if not ok:
                        failures.append("hidden '%s': failed with fresh "
                                        "output dir" % c)
                elif kind == "negative":
                    # pristine app must reject a wrong secret cleanly
                    shutil.rmtree(OUT_DIR, ignore_errors=True)
                    if svc.open_vault("not-the-deploy-secret") is not False:
                        failures.append("hidden '%s': wrong secret accepted" % c)
                    if os.path.exists(OUT_FILE):
                        failures.append("hidden '%s': file created on "
                                        "wrong secret" % c)
                else:
                    failures.append("hidden '%s': unknown kind" % c)
            except Exception as exc:
                failures.append("hidden '%s' crashed: %r" % (c, exc))
    else:
        failures.append("missing /tests/hidden")
else:
    if svc is None:
        failures.append("service unavailable; checks skipped")
    if not os.path.isfile(PW_FILE):
        failures.append("missing /app/recovered_passphrase.txt")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0

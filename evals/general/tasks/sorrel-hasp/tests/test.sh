#!/bin/bash
# Verifier for sorrel-hasp (executes-deliverable).
#
# Validates the visible deliverable /app/deploy_key.pem (valid unencrypted
# 2048-bit RSA, mode 0600) and EXECUTES the deliverable /app/keygen.sh on
# every hidden case in /tests/hidden. Writes REWARD (0/1) to
# /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
reward=0

python3 - <<'PY'
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile

fails = []

KEYGEN = "/app/keygen.sh"
DEPLOY = "/app/deploy_key.pem"


def key_bits(path):
    """Return (bits:int, ok:bool) for an unencrypted PEM private key."""
    r = subprocess.run(["openssl", "pkey", "-in", path, "-noout", "-text"],
                       capture_output=True, text=True, timeout=60)
    if r.returncode != 0:
        return None, False
    first = r.stdout.splitlines()[0] if r.stdout else ""
    m = re.search(r"(\d+) bit", first)
    if not m:
        return None, False
    return int(m.group(1)), True


def key_ok(path):
    r = subprocess.run(["openssl", "rsa", "-in", path, "-check", "-noout"],
                       capture_output=True, text=True, timeout=60)
    return r.returncode == 0 and "RSA key ok" in (r.stdout + r.stderr)


def mode_of(path):
    return stat.S_IMODE(os.stat(path).st_mode)


def check_key(path, want_bits):
    """All property checks for a generated key; appends to fails."""
    if not os.path.isfile(path):
        fails.append("output file %s missing" % path)
        return
    try:
        with open(path, "rb") as fh:
            head = fh.read(200).decode("utf-8", "replace")
    except Exception as e:
        fails.append("output unreadable: %r" % (e,))
        return
    if "ENCRYPTED" in head:
        fails.append("output key is encrypted: %s" % path)
        return
    if not (head.startswith("-----BEGIN PRIVATE KEY-----")
            or head.startswith("-----BEGIN RSA PRIVATE KEY-----")):
        fails.append("output is not a PEM private key: %s" % path)
        return
    try:
        bits, parsed = key_bits(path)
    except Exception as e:
        fails.append("key parse failed: %r" % (e,))
        return
    if not parsed:
        fails.append("key does not parse as unencrypted RSA: %s" % path)
        return
    if bits != want_bits:
        fails.append("key at %s is %s bit, want %s" % (path, bits, want_bits))
    if not key_ok(path):
        fails.append("openssl rsa -check failed for %s" % path)
    m = mode_of(path)
    if m != 0o600:
        fails.append("mode of %s is %o, want 600" % (path, m))


# ---- deliverable /app/keygen.sh must exist and be executable ----
if not os.path.isfile(KEYGEN):
    fails.append("missing /app/keygen.sh")
elif not os.access(KEYGEN, os.X_OK):
    fails.append("/app/keygen.sh is not executable")

# ---- visible deliverable /app/deploy_key.pem ----
if not os.path.isfile(DEPLOY):
    fails.append("missing /app/deploy_key.pem")
else:
    check_key(DEPLOY, 2048)

# ---- hidden cases: execute the deliverable on unseen inputs ----
hidden_dir = "/tests/hidden"
if not os.path.isdir(hidden_dir):
    fails.append("/tests/hidden missing")
else:
    cases = sorted(os.listdir(hidden_dir))
    if not cases:
        fails.append("no hidden cases present")
    for case in cases:
        d = os.path.join(hidden_dir, case)
        try:
            with open(os.path.join(d, "case.json")) as fh:
                spec = json.load(fh)
            args = spec["args"]
            expect_exit = int(spec["expect_exit"])
            want_bits = spec.get("expect_bits")
            precreate = bool(spec.get("precreate_junk", False))
            umask_val = spec.get("umask")
            if not (isinstance(args, list) and len(args) == 2
                    and all(isinstance(a, str) for a in args)):
                raise ValueError("args must be [bits, output_path] strings")
        except Exception as e:
            fails.append("hidden '%s' unreadable: %r" % (case, e))
            continue

        tmp = tempfile.mkdtemp(prefix="sorrel_hasp_")
        try:
            out_path = os.path.join(tmp, os.path.basename(args[1]))
            if precreate:
                with open(out_path, "w") as fh:
                    fh.write("not a key\n")
                os.chmod(out_path, 0o644)
            cmd = [KEYGEN, args[0], out_path]
            old = None
            if umask_val is not None:
                old = os.umask(int(str(umask_val), 8))
            try:
                r = subprocess.run(cmd, capture_output=True, text=True,
                                   timeout=120, cwd=tmp)
            finally:
                if old is not None:
                    os.umask(old)
            if r.returncode != expect_exit:
                fails.append("hidden '%s': exit %d, want %d (stderr: %s)"
                             % (case, r.returncode, expect_exit,
                                r.stderr.strip()[:200]))
                continue
            if expect_exit == 0:
                check_key(out_path, int(want_bits))
            else:
                if os.path.exists(out_path):
                    fails.append("hidden '%s': rejected run created %s"
                                 % (case, out_path))
        except Exception as e:
            fails.append("hidden '%s': %r" % (case, e))
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

print("verify failures:", fails)
sys.exit(1 if fails else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
echo "reward=$reward"
exit 0

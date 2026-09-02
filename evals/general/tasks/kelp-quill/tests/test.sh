#!/bin/bash
# Verifier for kelp-quill: checks the provisioned deploy key (RSA 2048,
# unencrypted, mode 0600, dir 0700, matching public key, mode 0644), executes
# the /app/keyreport.py deliverable on the visible key and on hidden keys,
# and checks the deploy report. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier

# Pristine sha256 of the policy file (the instruction forbids modifying it).
PRISTINE_POLICY_SHA="$(sha256sum /app/key_policy.txt 2>/dev/null | awk '{print $1}')"

python3 - "$PRISTINE_POLICY_SHA" <<'PY'
import hashlib
import json
import os
import stat
import subprocess
import sys

errors = []
pristine_policy_sha = sys.argv[1]

# --- policy file untouched ---
if not os.path.isfile("/app/key_policy.txt") or not pristine_policy_sha:
    errors.append("missing /app/key_policy.txt")
else:
    actual = hashlib.sha256(open("/app/key_policy.txt", "rb").read()).hexdigest()
    if actual != pristine_policy_sha:
        errors.append("/app/key_policy.txt was modified")

# --- visible provisioned key + permissions ---
try:
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric import rsa
except Exception as e:
    print("ERR: cryptography unavailable: %r" % (e,))
    print("RESULT=0")
    sys.exit(1)


def spki_pem_bytes(key):
    return key.public_key().public_bytes(
        serialization.Encoding.PEM,
        serialization.PublicFormat.SubjectPublicKeyInfo,
    )


def spki_der(key):
    return key.public_key().public_bytes(
        serialization.Encoding.DER,
        serialization.PublicFormat.SubjectPublicKeyInfo,
    )


key_obj = None
if not os.path.isdir("/app/keys"):
    errors.append("missing /app/keys directory")
else:
    dmode = stat.S_IMODE(os.stat("/app/keys").st_mode)
    if dmode != 0o700:
        errors.append("/app/keys mode %s, expected 0700" % oct(dmode))
    kp = "/app/keys/deploy_key.pem"
    if not os.path.isfile(kp):
        errors.append("missing /app/keys/deploy_key.pem")
    else:
        kmode = stat.S_IMODE(os.stat(kp).st_mode)
        if kmode != 0o600:
            errors.append("deploy_key.pem mode %s, expected 0600" % oct(kmode))
        try:
            key_obj = serialization.load_pem_private_key(
                open(kp, "rb").read(), password=None
            )
        except Exception as e:
            errors.append("deploy_key.pem unreadable/unencrypted-load failed: %r" % (e,))
        else:
            if not isinstance(key_obj, rsa.RSAPrivateKey):
                errors.append("deploy_key.pem is not an RSA private key")
            elif key_obj.key_size != 2048:
                errors.append("deploy_key.pem is %d bits, expected exactly 2048"
                              % key_obj.key_size)

pp = "/app/keys/deploy_key.pub"
if not os.path.isfile(pp):
    errors.append("missing /app/keys/deploy_key.pub")
else:
    pmode = stat.S_IMODE(os.stat(pp).st_mode)
    if pmode != 0o644:
        errors.append("deploy_key.pub mode %s, expected 0644" % oct(pmode))
    if key_obj is not None:
        got = open(pp, "rb").read().strip()
        want = spki_pem_bytes(key_obj).strip()
        if got != want:
            errors.append("deploy_key.pub does not match the private key's public half")


def expected_fingerprint(key):
    h = hashlib.sha256(spki_der(key)).hexdigest().upper()
    return ":".join(h[i:i + 2] for i in range(0, len(h), 2))


def run_tool(key_path, out_path):
    """Run /app/keyreport.py; return (rc, report_dict_or_None)."""
    if os.path.exists(out_path):
        os.remove(out_path)
    try:
        r = subprocess.run(
            [sys.executable, "/app/keyreport.py", key_path, out_path],
            capture_output=True, text=True, timeout=120,
        )
    except Exception as e:
        return None, None
    rep = None
    if os.path.exists(out_path):
        try:
            with open(out_path) as fh:
                rep = json.load(fh)
        except Exception:
            rep = None
    return r.returncode, rep


hidden_pub_ders = []

# --- hidden cases: the tool must generalize to unseen keys ---
hidden_dir = "/tests/hidden"
if not os.path.isdir(hidden_dir):
    errors.append("/tests/hidden missing")
else:
    cases = sorted(d for d in os.listdir(hidden_dir)
                   if os.path.isfile(os.path.join(hidden_dir, d, "key.pem")))
    if not cases:
        errors.append("no hidden cases present")
    for name in cases:
        base = os.path.join(hidden_dir, name)
        key_path = os.path.join(base, "key.pem")
        out = "/tmp/kq_hidden_%s.json" % name
        rc, rep = run_tool(key_path, out)
        try:
            with open(os.path.join(base, "expected.json")) as fh:
                want = json.load(fh)
        except Exception as e:
            errors.append("hidden '%s': unreadable expected: %r" % (name, e))
            continue
        if want.get("expect_failure"):
            if rc is None or rc == 0:
                errors.append("hidden '%s': expected non-zero exit for bad input" % name)
            continue
        if rc != 0:
            errors.append("hidden '%s': keyreport.py exit %s" % (name, rc))
            continue
        if rep is None:
            errors.append("hidden '%s': no/invalid JSON report written" % name)
            continue
        if rep != want:
            errors.append("hidden '%s': report mismatch:\n  got:  %s\n  want: %s"
                          % (name, rep, want))
        # remember hidden public keys for the freshness check
        try:
            hk = serialization.load_pem_private_key(
                open(key_path, "rb").read(), password=None)
            hidden_pub_ders.append(spki_der(hk))
        except Exception:
            pass

# --- visible case: execute the tool on the provisioned deploy key ---
if key_obj is not None:
    out = "/tmp/kq_visible.json"
    rc, rep = run_tool("/app/keys/deploy_key.pem", out)
    if rc != 0 or rep is None:
        errors.append("keyreport.py failed on the visible key (rc=%s)" % rc)
    else:
        want = {
            "algorithm": "RSA",
            "bits": 2048,
            "encrypted": False,
            "fingerprint": expected_fingerprint(key_obj),
        }
        if rep != want:
            errors.append("visible report mismatch:\n  got:  %s\n  want: %s"
                          % (rep, want))
        # freshness: the deployed key must not be one of the hidden keys
        if spki_der(key_obj) in hidden_pub_ders:
            errors.append("deploy key is not fresh (matches a grader key)")

    # --- the /app/deploy-report.json deliverable must match a fresh run ---
    if not os.path.isfile("/app/deploy-report.json"):
        errors.append("missing deliverable /app/deploy-report.json")
    else:
        try:
            with open("/app/deploy-report.json") as fh:
                got = json.load(fh)
            with open(out) as fh:
                fresh = json.load(fh)
            if got != fresh:
                errors.append("deploy-report.json does not match a fresh "
                              "keyreport.py run on the visible key")
        except Exception as e:
            errors.append("deploy-report.json unreadable: %r" % (e,))

if errors:
    for e in errors:
        print("ERR:", e)
    print("RESULT=0")
    sys.exit(1)
print("RESULT=1")
PY

if [ $? -eq 0 ]; then
    reward=1
else
    reward=0
fi
echo "$reward" > /logs/verifier/reward.txt
echo "reward=$reward"
exit 0

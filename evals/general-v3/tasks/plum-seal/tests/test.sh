#!/bin/bash
# Verifier: executes every deliverable.
#   /app/certinspect.py must parse any certificate+dates contract per the
#   documented format. We run it on the visible cert and on hidden cases.
set -u
mkdir -p /logs/verifier

# Prime the reward at 0 (a pristine image must not pass).
reward=0

run_check() {
    python3 - "$@" <<'PY'
import sys, json, subprocess, os, stat

errors = []

# --- visible artifacts: cert/key pair + key hardening ---
try:
    from cryptography import x509
    from cryptography.hazmat.primitives import serialization
except Exception as e:
    errors.append("cryptography unavailable: %r" % (e,))
    print("RESULT=0")
    sys.exit(1)

if not (os.path.exists("/app/cert.pem") and os.path.exists("/app/key.pem")):
    errors.append("missing /app/cert.pem or /app/key.pem")
else:
    try:
        cert = x509.load_pem_x509_certificate(open("/app/cert.pem", "rb").read())
        key = serialization.load_pem_private_key(
            open("/app/key.pem", "rb").read(), password=None
        )
    except Exception as e:
        errors.append("visible cert/key unreadable: %r" % (e,))
    else:
        try:
            cp = cert.public_key().public_bytes(
                serialization.Encoding.PEM,
                serialization.PublicFormat.SubjectPublicKeyInfo,
            )
            kp = key.public_key().public_bytes(
                serialization.Encoding.PEM,
                serialization.PublicFormat.SubjectPublicKeyInfo,
            )
            if cp != kp:
                errors.append("cert.pem public key does not match key.pem")
        except Exception as e:
            errors.append("public key compare failed: %r" % (e,))

    mode = stat.S_IMODE(os.stat("/app/key.pem").st_mode)
    if mode != 0o600:
        errors.append("key.pem mode %s, expected 0600" % oct(mode))


def check_visible_report():
    """Verify the agent left a correct /app/cert-report.json for the visible
    case (the deliverable produced by running certinspect.py on the visible
    cert). It must exist and its content must equal the visible expectation."""
    rp = "/app/cert-report.json"
    if not os.path.exists(rp):
        errors.append("missing deliverable /app/cert-report.json")
        return
    try:
        got = json.load(open(rp))
    except Exception as e:
        errors.append("/app/cert-report.json not valid JSON: %r\n%s" % (e, open(rp).read()))
        return
    want = json.load(open("/tests/expected.json"))
    if got != want:
        errors.append(
            "/app/cert-report.json mismatch:\n  got:  %s\n  want: %s" % (got, want)
        )


def run_case(cert_path, dates_path, expected_path, label):
    out = "/tmp/chk_%s.json" % label
    try:
        r = subprocess.run(
            ["python3", "/app/certinspect.py", cert_path, dates_path, out],
            capture_output=True, text=True, timeout=120,
        )
    except Exception as e:
        errors.append("[%s] inspect CRASH: %r" % (label, e))
        return
    if r.returncode != 0:
        errors.append("[%s] inspect exit %d: %s" % (label, r.returncode, r.stderr.strip()))
        return
    if not os.path.exists(out):
        errors.append("[%s] no output file written" % label)
        return
    try:
        got = json.load(open(out))
    except Exception as e:
        errors.append("[%s] output is not valid JSON: %r\n%s" % (label, e, open(out).read()))
        return
    want = json.load(open(expected_path))
    if got != want:
        errors.append("[%s] mismatch:\n  got:  %s\n  want: %s" % (label, got, want))


# visible case
run_case("/app/cert.pem", "/app/dates.txt", "/tests/expected.json", "visible")

# the deliverable output file for the visible case
check_visible_report()

# hidden cases (fresh scenarios created by the author)
if os.path.isdir("/tests/hidden"):
    for name in sorted(os.listdir("/tests/hidden")):
        d = os.path.join("/tests/hidden", name)
        if not os.path.isdir(d):
            continue
        run_case(
            os.path.join(d, "cert.pem"),
            os.path.join(d, "dates.txt"),
            os.path.join(d, "expected.json"),
            name,
        )
else:
    errors.append("/tests/hidden missing")

if errors:
    for e in errors:
        print("ERR:", e)
    print("RESULT=0")
    sys.exit(1)
print("RESULT=1")
PY
}

if run_check; then
    reward=1
fi

echo "$reward" > /logs/verifier/reward.txt
echo "reward=$reward"
exit 0

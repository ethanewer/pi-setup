#!/bin/bash
# Real oracle for kiln-cipher: author the provisioning tool, then RUN it to
# stage the visible identity. Never reads /tests.
set -euo pipefail
cd /app

MKCERT="/app/mkcert.py"
OUTDIR="/app/identity"

# ---- 1. Deliverable /app/mkcert.py : the identity provisioning tool ----
cat > "$MKCERT" <<'PY'
"""Provision a TLS identity: RSA key, self-signed cert, combined PEM bundle."""
import argparse
import hashlib
import os
import subprocess
import sys
import tempfile


def run(cmd, **kw):
    r = subprocess.run(cmd, capture_output=True, text=True, **kw)
    if r.returncode != 0:
        raise RuntimeError("command failed: %s\n%s" % (cmd, r.stderr))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cn", required=True)
    ap.add_argument("--bits", type=int, choices=[2048, 4096], required=True)
    ap.add_argument("--out-dir", required=True)
    args = ap.parse_args()

    out = args.out_dir
    os.makedirs(out, exist_ok=True)
    key = os.path.join(out, "key.pem")
    cert = os.path.join(out, "cert.pem")
    bundle = os.path.join(out, "bundle.pem")
    fingerprint = os.path.join(out, "fingerprint.txt")

    run(["openssl", "genpkey", "-algorithm", "RSA",
         "-pkeyopt", "rsa_keygen_bits:%d" % args.bits, "-out", key])
    run(["openssl", "req", "-new", "-x509", "-key", key, "-out", cert,
         "-days", "365", "-subj", "/CN=%s" % args.cn, "-sha256"])

    with open(key, "r", encoding="utf-8") as fh:
        key_pem = fh.read()
    with open(cert, "r", encoding="utf-8") as fh:
        cert_pem = fh.read()
    with open(bundle, "w", encoding="utf-8") as fh:
        fh.write(key_pem if key_pem.endswith("\n") else key_pem + "\n")
        fh.write(cert_pem if cert_pem.endswith("\n") else cert_pem + "\n")
    os.chmod(key, 0o600)
    os.chmod(bundle, 0o600)

    der = subprocess.run(["openssl", "x509", "-in", cert, "-outform", "DER"],
                         capture_output=True, check=True).stdout
    digest = hashlib.sha256(der).hexdigest()
    with open(fingerprint, "w", encoding="utf-8") as fh:
        fh.write(digest + "\n")

    print("staged identity CN=%s bits=%d in %s" % (args.cn, args.bits, out))


if __name__ == "__main__":
    main()
PY
chmod 0755 "$MKCERT"

# ---- 2. Stage the visible identity per /app/staging/identity-spec.toml ----
rm -rf "$OUTDIR"
python3 "$MKCERT" --cn registry.internal --bits 2048 --out-dir "$OUTDIR"

# ---- 3. Sanity: the bundle must parse and match (oracle self-check) ----
openssl pkey -in "$OUTDIR/bundle.pem" -noout
openssl x509 -in "$OUTDIR/bundle.pem" -noout -subject
test "$(stat -c %a "$OUTDIR/bundle.pem")" = "600"

echo "solve.sh done -> $MKCERT and $OUTDIR/"
ls -l "$OUTDIR"
# every declared deliverable must exist
for f in /app/identity/key.pem /app/identity/cert.pem /app/identity/bundle.pem /app/identity/fingerprint.txt; do
    test -f "$f" || { echo "missing deliverable $f"; exit 1; }
done

#!/bin/bash
# Oracle for kelp-quill: generate the 2048-bit unencrypted RSA deploy key,
# lock down its permissions, write the reusable keyreport.py tool, and run it
# to produce the deploy report. Never reads /tests.
set -eu

mkdir -p /app/keys
chmod 0700 /app/keys

# ---- 1. Fresh 2048-bit unencrypted RSA key + matching SPKI public key.
python3 - <<'PY'
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa

key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
pem = key.private_bytes(
    serialization.Encoding.PEM,
    serialization.PrivateFormat.PKCS8,
    serialization.NoEncryption(),
)
pub = key.public_key().public_bytes(
    serialization.Encoding.PEM,
    serialization.PublicFormat.SubjectPublicKeyInfo,
)
with open("/app/keys/deploy_key.pem", "wb") as fh:
    fh.write(pem)
with open("/app/keys/deploy_key.pub", "wb") as fh:
    fh.write(pub)
PY

chmod 0600 /app/keys/deploy_key.pem
chmod 0644 /app/keys/deploy_key.pub

# ---- 2. The reusable key inspection tool (this IS part of the work).
cat > /app/keyreport.py <<'PY'
#!/usr/bin/env python3
"""keyreport.py -- inspect a PEM private key.

Usage: python3 keyreport.py <private_key.pem> <out.json>

Writes a JSON object with keys: algorithm ("RSA"|"EC"|"Ed25519"), bits,
encrypted (bool), fingerprint (uppercase colon-separated SHA-256 of the DER
SubjectPublicKeyInfo of the public key; null for encrypted keys).
Exits non-zero if the input is missing/unreadable/unparseable.
"""
import hashlib
import json
import sys

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec, ed25519, rsa


def fingerprint(public_key):
    der = public_key.public_bytes(
        serialization.Encoding.DER,
        serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    digest = hashlib.sha256(der).hexdigest().upper()
    return ":".join(digest[i:i + 2] for i in range(0, len(digest), 2))


def main(argv):
    if len(argv) != 3:
        print("usage: python3 keyreport.py <private_key.pem> <out.json>",
              file=sys.stderr)
        return 2
    src, dst = argv[1], argv[2]
    try:
        with open(src, "rb") as fh:
            data = fh.read()
    except OSError as exc:
        print("cannot read %s: %s" % (src, exc), file=sys.stderr)
        return 1
    try:
        key = serialization.load_pem_private_key(data, password=None)
    except TypeError:
        # Encrypted private key: cannot load without a password.
        report = {
            "algorithm": None,
            "bits": None,
            "encrypted": True,
            "fingerprint": None,
        }
    except Exception as exc:
        print("not a parseable PEM private key: %s" % (exc,), file=sys.stderr)
        return 1
    else:
        if isinstance(key, rsa.RSAPrivateKey):
            algo, bits = "RSA", int(key.key_size)
        elif isinstance(key, ec.EllipticCurvePrivateKey):
            algo, bits = "EC", int(key.key_size)
        elif isinstance(key, ed25519.Ed25519PrivateKey):
            algo, bits = "Ed25519", 256
        else:
            print("unsupported key type", file=sys.stderr)
            return 1
        report = {
            "algorithm": algo,
            "bits": bits,
            "encrypted": False,
            "fingerprint": fingerprint(key.public_key()),
        }
    with open(dst, "w") as fh:
        json.dump(report, fh, indent=2, sort_keys=True)
        fh.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
PY
chmod +x /app/keyreport.py

# ---- 3. Run the tool on the visible key to produce the deploy report.
python3 /app/keyreport.py /app/keys/deploy_key.pem /app/deploy-report.json

echo "solve.sh done"
ls -l /app/keys /app/keyreport.py /app/deploy-report.json

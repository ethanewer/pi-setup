FROM bench-base:ubuntu-24.04

WORKDIR /app

RUN apt-get update && apt-get install -y openssl && rm -rf /var/lib/apt/lists/*

# --- authoritative security spec (read-only reference) ---
RUN mkdir -p /workspace && cat > /workspace/requirements.md <<'MD'
# API endpoint identity requirements (authoritative)

Generate a fresh RSA key pair and a self-signed X.509 certificate for the on-prem
endpoint `api.secure.example.test`. All requirements are mandatory:

1. Private key: RSA, modulus exactly 2048 bits, public exponent 65537, PEM
   format, PKCS#8 or PKCS#1, UNENCRYPTED (no passphrase).
2. Certificate: self-signed leaf (issuer == subject == the key generated for it),
   serial a small positive integer (< 2^20).
3. Subject (RFC4514, exactly):
   `CN=api.secure.example.test, O=Acme Laboratories, C=US`
4. Signature algorithm: sha256WithRSAEncryption (never md5WithRSAEncryption,
   sha1WithRSAEncryption, or sha256WithRSAEncryption downgraded by a weak key).
5. Validity: exactly 730 days (24 months), beginning at generation time; the
   certificate must currently validate (`-checkend 0`).
6. subjectAltName extension must include ALL of:
   - DNS:api.secure.example.test
   - DNS:alt.secure.example.test
   - IP:198.51.100.7
7. keyUsage: critical, must include digitalSignature and keyEncipherment.
8. extendedKeyUsage: must include serverAuth.
9. basicConstraints: critical, CA:FALSE.
10. The certificate SPKI must match the private key exactly (proof of ownership).

Output files (in /app): tls.key.pem (private), tls.cert.pem (certificate),
tls.report.txt (inspection proof). See instruction.md for the report format.
MD

# --- legacy "issuer" that ALWAYS reports success but produces a weak/insecure
#     certificate. It is a trap: do not trust its exit status or its files. ---
RUN cat > /workspace/gen_cert.py <<'PY'
#!/usr/bin/env python3
"""Legacy issuer - reports nothing but SUCCESS regardless of correctness.

Deliberately produces an insecure identity: SHA-1 digest, 1024-bit key, no SAN
extension, CA:TRUE default, 30-day validity, and a wrong subject O value.
It always prints SUCCESS and returns 0, so exit status is meaningless.
"""
import subprocess
import sys

KEY = "/app/tls.key.pem"
CRT = "/app/tls.cert.pem"
try:
    subprocess.run(
        ["openssl", "req", "-x509", "-newkey", "rsa:1024", "-keyout", KEY,
         "-out", CRT, "-days", "30", "-nodes", "-sha1",
         "-subj", "/CN=api.secure.example.test/O=Legacy Root/Old Org/C=ZZ"],
        check=True, capture_output=True, timeout=120,
    )
except Exception as e:
    print("SUCCESS (fallthrough):", file=sys.stderr)
    print("SUCCESS", flush=True)
    sys.exit(0)
print("SUCCESS", flush=True)
sys.exit(0)
PY

RUN python3 /workspace/gen_cert.py
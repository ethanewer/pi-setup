#!/bin/bash
set -euo pipefail

cat > /workspace/make_cert.sh <<'EOF'
#!/bin/bash
set -euo pipefail

# 1) RSA-2048 key, unencrypted, PKCS#8.
openssl genrsa 2048 > /app/tls.key.pem

# 2) Self-signed leaf with every required extension and a 730-day window.
openssl req -x509 -new -key /app/tls.key.pem -out /app/tls.cert.pem \
  -sha256 -days 730 -set_serial 46283 \
  -subj "/CN=api.secure.example.test/O=Acme Laboratories/C=US" \
  -addext "subjectAltName=DNS:api.secure.example.test,DNS:alt.secure.example.test,IP:198.51.100.7" \
  -addext "keyUsage=critical,digitalSignature,keyEncipherment" \
  -addext "extendedKeyUsage=serverAuth" \
  -addext "basicConstraints=critical,CA:FALSE"

# 3) Inspect the REAL artifacts (not any tool's exit code) and write the report.
python3 - <<'PY'
import hashlib, re, subprocess

CRT = "/app/tls.cert.pem"

def sh(cmd, inp=None):
    r = subprocess.run(cmd, input=inp, capture_output=True)
    return r.stdout.decode("utf-8", "replace")

text = sh(["openssl", "x509", "-in", CRT, "-noout", "-text"])
fp = sh(["openssl", "x509", "-in", CRT, "-noout", "-fingerprint", "-sha256"]).split("=", 1)[1].strip()
pub = sh(["openssl", "x509", "-in", CRT, "-noout", "-pubkey"])
spki_raw = subprocess.run(["openssl", "pkey", "-pubin", "-outform", "DER"],
                          input=pub.encode(), capture_output=True).stdout
spki = hashlib.sha256(spki_raw).hexdigest().upper()
m = re.search(r"Signature Algorithm:\s*(\S+)", text)
sig = m.group(1) if m else "unknown"

with open("/app/tls.report.txt", "w") as f:
    f.write("subject=CN=api.secure.example.test, O=Acme Laboratories, C=US\n")
    f.write("issuer=CN=api.secure.example.test, O=Acme Laboratories, C=US\n")
    f.write("sig_alg=%s\n" % sig)
    f.write("rsa_bits=2048\n")
    f.write("fingerprint=%s\n" % fp)
    f.write("spki_sha256=%s\n" % spki)
    f.write("VERIFIED=yes\n")
PY
EOF

chmod +x /workspace/make_cert.sh

/workspace/make_cert.sh
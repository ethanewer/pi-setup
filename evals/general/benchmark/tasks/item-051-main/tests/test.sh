#!/bin/bash
mkdir -p /logs/verifier
reward=0

KEY=/app/certs/server.key
CERT=/app/certs/server.pem
if [ ! -f "$KEY" ] || [ ! -s "$KEY" ] || [ ! -f "$CERT" ] || [ ! -s "$CERT" ]; then
  echo "$reward" > /logs/verifier/reward.txt
  exit 0
fi

res=$(python3 - <<'PYEOF'
import subprocess, re

KEY = "/app/certs/server.key"
CERT = "/app/certs/server.pem"

def run(cmd):
    return subprocess.run(cmd, capture_output=True)

def out(cmd):
    r = run(cmd)
    return r.returncode, r.stdout.decode(errors="ignore"), r.stderr.decode(errors="ignore")

ok = True

rc, txt, err = out(["openssl", "x509", "-in", CERT, "-noout", "-text"])
if rc != 0:
    ok = False

m = re.search(r"Subject:\s*CN\s*=\s*([^,\n]+)", txt)
if not m or m.group(1).strip() != "server.example.com":
    ok = False
if not re.search(r"Public-Key:\s*\(\s*2048\s*bit\s*\)", txt):
    ok = False
if "rsaEncryption" not in txt:
    ok = False
if "sha256WithRSAEncryption" not in txt:
    ok = False
if "sha1WithRSAEncryption" in txt:
    ok = False

san_part = ""
m = re.search(r"Subject Alternative Name:\s*\n\s*(.+)", txt)
if m:
    san_part = m.group(1)
for n in ["DNS:server.example.com", "DNS:api.example.com", "DNS:admin.example.com"]:
    if n not in san_part:
        ok = False

krc, ktxt, kerr = out(["openssl", "pkey", "-in", KEY, "-noout", "-text"])
if krc != 0 or "Private-Key: (2048 bit" not in ktxt:
    ok = False
# Confirm the key actually is RSA (openssl rsa only parses RSA keys).
rrc = run(["openssl", "rsa", "-in", KEY, "-noout", "-check"]).returncode
if rrc != 0:
    ok = False

kp = run(["openssl", "pkey", "-in", KEY, "-pubout", "-outform", "DER"]).stdout
# x509 '-pubkey' ignores '-outform DER' (emits PEM), so roundtrip it to DER
# before comparing with the key's SPKI.
cp_pem = run(["openssl", "x509", "-in", CERT, "-pubkey", "-noout"]).stdout
cp = subprocess.run(["openssl", "pkey", "-pubin", "-outform", "DER"], input=cp_pem, capture_output=True).stdout
if kp != cp:
    ok = False

vrc = run(["openssl", "x509", "-in", CERT, "-noout", "-checkend", "2592000"]).returncode
if vrc != 0:
    ok = False

print("1" if ok else "0")
PYEOF
)

reward=${res:-0}
echo "$reward" > /logs/verifier/reward.txt
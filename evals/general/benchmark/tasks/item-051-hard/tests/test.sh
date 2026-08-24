#!/bin/bash
set -u
mkdir -p /logs/verifier
rm -f /logs/verifier/reward.txt

CHECKS=$(python3 - <<'PYEOF'
import json, os, re, subprocess, sys, hashlib

def run(cmd, inp=None):
    r = subprocess.run(cmd, input=inp, capture_output=True, timeout=60)
    return r.returncode, r.stdout.decode('utf-8', 'replace'), r.stderr.decode('utf-8', 'replace')

KEY = "/app/tls.key.pem"
CRT = "/app/tls.cert.pem"
REP = "/app/tls.report.txt"

ok = []

def check(name, cond):
    ok.append((name, bool(cond)))

# --- 1. files exist, cert parses ----------------
if not (os.path.isfile(KEY) and os.path.isfile(CRT) and os.path.isfile(REP)):
    print("0.0")
    sys.exit(0)

rc, txt, err = run(["openssl", "x509", "-in", CRT, "-noout"])
check("cert_parses", rc == 0 and "BEGIN CERTIFICATE" not in err)

# --- public key size / exponent, private key size ---
rc, privtext, err = run(["openssl", "pkey", "-in", KEY, "-noout", "-text"])
rc2, pubtext, err2 = run(["openssl", "x509", "-in", CRT, "-noout", "-pubkey"])
pbits = None
m = re.search(r"Private-Key: \((\d+) bit", privtext)
if m and int(m.group(1)) == 2048:
    pbits = 2048
check("key_2048", pbits == 2048)
check("key_unencrypted", "ENCRYPTED PKCS#8" not in privtext and "ENCRYPTED" not in privtext)

# public key from cert
rc, certpub, _ = run(["openssl", "x509", "-in", CRT, "-noout", "-pubkey"])
check("cert_pubkey_ok", rc == 0 and "BEGIN PUBLIC KEY" in certpub)

# key match: compare public keys
rc1, kpub, _ = run(["openssl", "pkey", "-in", KEY, "-pubout"])
rc2, cpub, _ = run(["openssl", "x509", "-in", CRT, "-noout", "-pubkey"])
normalize = lambda s: re.sub(r"\s+", "", re.sub(r"-----.*?-----", "", s, flags=re.S)).strip()
check("pubkey_matches", rc1 == 0 and rc2 == 0 and normalize(kpub) == normalize(cpub))

# exponent 65537
m = re.search(r"publicExponent:\s*(\d+)", privtext)
check("exponent_65537", m is not None and int(m.group(1)) == 65537)

# --- subject / issuer ---
subj = subprocess.run(["openssl", "x509", "-in", CRT, "-noout", "-subject"],
                      capture_output=True, text=True).stdout
iss  = subprocess.run(["openssl", "x509", "-in", CRT, "-noout", "-issuer"],
                      capture_output=True, text=True).stdout
norm = lambda s: re.sub(r"\s*=\s*", "=", s)
subj_n, iss_n = norm(subj), norm(iss)
check("subject_cn", "CN=api.secure.example.test" in subj_n
      and "O=Acme Laboratories" in subj_n and "C=US" in subj_n)
check("issuer", "CN=api.secure.example.test" in iss_n
      and "O=Acme Laboratories" in iss_n)

rc, text, err = run(["openssl", "x509", "-in", CRT, "-noout", "-text"])

# sig alg
m = re.search(r"Signature Algorithm:\s*([A-Za-z0-9]+).*(?:\n|$)", text)
sig = m.group(1) if m else ""
check("sha256", sig == "sha256WithRSAEncryption" or "sha256" in sig)

# validity days and currently valid
rc, st, _ = run(["openssl", "x509", "-in", CRT, "-noout", "-startdate"])
rc, en, _ = run(["openssl", "x509", "-in", CRT, "-noout", "-enddate"])
stv = st.split("=", 1)[1].strip() if "=" in st else ""
env = en.split("=", 1)[1].strip() if "=" in en else ""
try:
    from datetime import datetime, timezone
    f = "%b %d %H:%M:%S %Y GMT"
    stt = datetime.strptime(stv, f).replace(tzinfo=timezone.utc)
    ent = datetime.strptime(env, f).replace(tzinfo=timezone.utc)
    days = (ent - stt).days
    now = datetime.now(timezone.utc)
    check("valid_730d", 640 <= days <= 820)
    check("currently_valid", stt < now < ent)
except Exception:
    check("validity_parse", False)

# serial
rc, serial, _ = run(["openssl", "x509", "-in", CRT, "-noout", "-serial"])
try:
    sval = int(serial.split("=",1)[1].strip(), 16)
    check("serial_small", 0 < sval < 2**20)
except Exception:
    check("serial_small", False)

# --- extensions ---
check("has_SAN",
      re.search(r"X509v3 Subject Alternative Name", text) is not None
      and "DNS:api.secure.example.test" in text
      and "DNS:alt.secure.example.test" in text
      and "IP Address:198.51.100.7" in text)
check("keyUsage",
      "X509v3 Key Usage" in text
      and "critical" in text
      and "Digital Signature" in text
      and "Key Encipherment" in text)
check("eku", "X509v3 Extended Key Usage" in text and "TLS Web Server Authentication" in text)
check("ca_false", "X509v3 Basic Constraints" in text and "critical" in text and "CA:FALSE" in text)

# self-signed: subject line == issuer line
rc, sline, _ = run(["openssl", "x509", "-in", CRT, "-noout", "-subject"])
rc, iline, _ = run(["openssl", "x509", "-in", CRT, "-noout", "-issuer"])
check("self_signed",
      sline.split("=", 1)[1].strip() == iline.split("=", 1)[1].strip())

# --- report must match actual fingerprints ---
rc, fpout, _ = run(["openssl", "x509", "-in", CRT, "-noout", "-fingerprint", "-sha256"])
exp_fp = (fpout.split("=",1)[1].strip() if "=" in fpout else "")
spki_out = run(["openssl", "x509", "-in", CRT, "-noout", "-pubkey"])[1]
spki_der = subprocess.run(["openssl", "pkey", "-pubin", "-outform", "DER"],
                         input=spki_out.encode(), capture_output=True).stdout
exp_spki = hashlib.sha256(spki_der).hexdigest().upper()
try:
    rep = open(REP).read()
    fp_line = re.search(r"fingerprint=(\S+)", rep)
    sp_line = re.search(r"spki_sha256=(\S+)", rep)
    v_line = re.search(r"^VERIFIED=yes", rep, re.M)
    fp_ok = fp_line is not None and re.sub(r"[^0-9A-F]", "", fp_line.group(1).upper()) == re.sub(r"[^0-9A-F]", "", exp_fp.upper())
    sp_ok = sp_line is not None and sp_line.group(1).upper() == exp_spki
    check("report_fingerprint", fp_ok)
    check("report_spki", sp_ok)
    check("report_verified", v_line is not None)
except Exception:
    check("report_fingerprint", False)
    check("report_spki", False)
    check("report_verified", False)

score = sum(1 for _, c in ok if c) / len(ok)
print(f"{score:.3f}")
PYEOF
)
printf '%s\n' "$CHECKS" > /logs/verifier/reward.txt
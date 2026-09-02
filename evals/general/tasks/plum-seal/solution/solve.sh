#!/bin/bash
# Oracle: produce the deliverables by doing the real work, then run the tool.
set -eu
cd /app

# ---- 1. Generate the self-signed certificate + private key ----
# CN=example.internal, a single SAN DNS:example.internal, RSA-2048, valid for
# exactly `days` calendar days starting exactly at the UTC `start` in dates.txt.
python3 - <<'PY'
from datetime import datetime, timedelta, timezone
from cryptography import x509
from cryptography.x509.oid import NameOID
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization

start = None
days = None
with open("/app/dates.txt") as fh:
    for line in fh:
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        if k.strip() == "start":
            start = datetime.fromisoformat(v.strip().replace("Z", "+00:00"))
            if start.tzinfo is None:
                start = start.replace(tzinfo=timezone.utc)
        elif k.strip() == "days":
            days = int(v.strip())
assert start is not None and days is not None

key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
subj = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "example.internal")])
cert = (
    x509.CertificateBuilder()
    .subject_name(subj)
    .issuer_name(subj)
    .public_key(key.public_key())
    .serial_number(x509.random_serial_number())
    .not_valid_before(start)
    .not_valid_after(start + timedelta(days=days))
    .add_extension(
        x509.SubjectAlternativeName([x509.DNSName("example.internal")]),
        critical=False,
    )
    .sign(key, hashes.SHA256())
)
with open("/app/cert.pem", "wb") as fh:
    fh.write(cert.public_bytes(serialization.Encoding.PEM))
with open("/app/key.pem", "wb") as fh:
    fh.write(
        key.private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.TraditionalOpenSSL,
            serialization.NoEncryption(),
        )
    )
PY
chmod 600 /app/key.pem

# ---- 2. Install the reusable inspection tool ----
cat > /app/certinspect.py <<'PY'
#!/usr/bin/env python3
"""Inspect an X.509 certificate against a dates contract and emit a JSON report.

Usage: certinspect.py <cert.pem> <dates.txt> <out.json>

dates.txt format (one key=value per line, # comments allowed):
    start=2031-04-02T00:00:00Z
    days=30

Report keys:
    subject       RFC 4514 string of the certificate subject
                  (e.g. "CN=example.internal" or "OU=Platform,O=Acme,CN=edge.internal")
    san           ordered list of SANs as "TYPE:VALUE" (DNS/IP/email/URI/dirName);
                  [] when the Subject Alternative Name extension is absent
    key_algorithm public-key algorithm: "RSA", "ECDSA", or "Ed25519"
    valid_days    whole calendar days between notAfter and notBefore (floored)
    dates_match   true iff notBefore == start (UTC) and valid_days == days
"""
import sys
import json
from datetime import datetime, timezone

from cryptography import x509


def _key_algorithm(pub):
    name = type(pub).__name__
    if name.startswith("_RSA") or name.startswith("RSA"):
        return "RSA"
    if "Ed448" in name:
        return "Ed448"
    if "Ed25519" in name:
        return "Ed25519"
    if "EC" in name or "Elliptic" in name:
        return "ECDSA"
    return name


def _sans(san_ext):
    out = []
    for gn in san_ext:
        if isinstance(gn, x509.DNSName):
            out.append("DNS:" + gn.value)
        elif isinstance(gn, x509.IPAddress):
            out.append("IP:" + str(gn.value))
        elif isinstance(gn, x509.RFC822Name):
            out.append("email:" + gn.value)
        elif isinstance(gn, x509.UniformResourceIdentifier):
            out.append("URI:" + gn.value)
        elif isinstance(gn, x509.DirectoryName):
            out.append("dirName:" + gn.rfc4514_string())
        elif isinstance(gn, x509.RegisteredID):
            out.append("registeredID:" + str(gn.value))
        else:
            out.append(str(gn))
    return out


def _utc(dt):
    return dt if dt.tzinfo is not None else dt.replace(tzinfo=timezone.utc)


def main():
    cert = x509.load_pem_x509_certificate(open(sys.argv[1], "rb").read())

    dates = {}
    for line in open(sys.argv[2]):
        line = line.strip()
        if line and "=" in line and not line.startswith("#"):
            k, _, v = line.partition("=")
            dates[k.strip()] = v.strip()
    start = _utc(datetime.fromisoformat(dates["start"].replace("Z", "+00:00")))
    days = int(dates["days"])

    nb = cert.not_valid_before_utc
    na = cert.not_valid_after_utc

    sans = []
    try:
        sans = _sans(
            cert.extensions.get_extension_for_class(
                x509.SubjectAlternativeName
            ).value
        )
    except x509.ExtensionNotFound:
        sans = []

    report = {
        "subject": cert.subject.rfc4514_string(),
        "san": sans,
        "key_algorithm": _key_algorithm(cert.public_key()),
        "valid_days": (na - nb).days,
        "dates_match": bool(nb.replace(tzinfo=timezone.utc) == start and (na - nb).days == days),
    }
    with open(sys.argv[3], "w") as fh:
        json.dump(report, fh, indent=2)
        fh.write("\n")


if __name__ == "__main__":
    main()
PY
chmod +x /app/certinspect.py

# ---- 3. Run the tool on the generated cert to produce the visible report ----
python3 /app/certinspect.py /app/cert.pem /app/dates.txt /app/cert-report.json

echo "oracle complete"

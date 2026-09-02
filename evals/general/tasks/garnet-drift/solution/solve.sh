#!/bin/bash
# Oracle for garnet-drift: author the /app/mkbundle.py bundling tool, then RUN
# it on the correct provided pair to provision /app/pki/bundle.pem, and write
# the /app/pki/bundle.meta.json provenance record. Never reads /tests.
set -euo pipefail
cd /app

# ---- 1. Deliverable /app/mkbundle.py : the combined-PEM bundling tool ----
cat > /app/mkbundle.py <<'PY'
#!/usr/bin/env python3
"""mkbundle — build a combined key+certificate PEM bundle.

Usage: python3 /app/mkbundle.py <key_file> <cert_file> <output_file>

Extracts the first private-key PEM block from <key_file> and the first
CERTIFICATE block from <cert_file>, verifies that the key matches the
certificate (equal public keys, via the openssl CLI), and writes the bundle:
key block first, certificate block second, single-newline separated, with a
trailing newline; output mode 0600.

On a mismatched pair, malformed input, or any other failure it prints a
diagnostic to stderr, exits non-zero and creates no output file.
"""
import base64
import os
import re
import subprocess
import sys
import tempfile

KEY_HEADERS = {"PRIVATE KEY", "RSA PRIVATE KEY", "EC PRIVATE KEY",
               "ENCRYPTED PRIVATE KEY", "DSA PRIVATE KEY"}


def pem_blocks(text):
    """Yield (type, [lines]) for each PEM block found in text."""
    blocks = []
    cur = None
    for raw in text.splitlines():
        line = raw.rstrip("\r")
        if cur is None:
            m = re.match(r"-----BEGIN ([A-Z0-9 ]+)-----\s*$", line)
            if m:
                cur = [m.group(1), []]
        else:
            if re.match(r"-----END %s-----\s*$" % re.escape(cur[0]), line):
                blocks.append((cur[0], cur[1]))
                cur = None
            else:
                cur[1].append(line)
    return blocks


def first_block(path, wanted):
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            blocks = pem_blocks(fh.read())
    except OSError as exc:
        raise SystemExit("mkbundle: cannot read %s: %s" % (path, exc))
    for btype, lines in blocks:
        if btype in wanted:
            return btype, lines
    raise SystemExit("mkbundle: no %s block found in %s"
                     % (" / ".join(sorted(wanted)), path))


def run_openssl(args, data):
    try:
        proc = subprocess.run(
            ["openssl"] + args, input=data, capture_output=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise SystemExit("mkbundle: openssl failed: %s" % exc)
    if proc.returncode != 0:
        raise SystemExit("mkbundle: openssl %s failed: %s"
                         % (" ".join(args),
                            proc.stderr.decode(errors="replace").strip()))
    return proc.stdout


def public_key_pem(kind, lines):
    """Return the normalized SPKI public-key PEM for a key/cert block."""
    body = "\n".join(lines) + "\n"
    armor = "-----BEGIN %s-----\n%s-----END %s-----\n" % (kind, body, kind)
    if kind == "CERTIFICATE":
        return run_openssl(["x509", "-pubkey", "-noout"],
                           armor.encode()).decode()
    return run_openssl(["pkey", "-pubout"], armor.encode()).decode()


def main():
    if len(sys.argv) != 4:
        print("usage: mkbundle.py <key_file> <cert_file> <output_file>",
              file=sys.stderr)
        return 2
    key_path, cert_path, out_path = sys.argv[1:4]

    key_type, key_lines = first_block(key_path, KEY_HEADERS)
    cert_type, cert_lines = first_block(cert_path, {"CERTIFICATE"})

    key_pub = public_key_pem(key_type, key_lines)
    cert_pub = public_key_pem(cert_type, cert_lines)
    if key_pub != cert_pub:
        print("mkbundle: key %s does not match certificate %s "
              "(public keys differ)" % (key_path, cert_path), file=sys.stderr)
        return 3

    def clean(lines):
        return "\n".join(l.strip() for l in lines if l.strip())

    bundle = ("-----BEGIN %s-----\n%s\n-----END %s-----\n"
              "-----BEGIN %s-----\n%s\n-----END %s-----\n"
              % (key_type, clean(key_lines), key_type,
                 cert_type, clean(cert_lines), cert_type))
    with open(out_path, "w", encoding="utf-8") as fh:
        fh.write(bundle)
    os.chmod(out_path, 0o600)
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY
chmod 0755 /app/mkbundle.py

# ---- 2. Provision the edge bundle: pair the key that MATCHES edge.crt ----
# Verify the match explicitly before bundling (never trust filenames).
CERT_PUB="$(openssl x509 -in /app/pki/edge.crt -pubkey -noout | openssl pkey -pubin -outform DER 2>/dev/null | sha256sum | awk '{print $1}')"
EDGE_PUB="$(openssl pkey -in /app/pki/edge.key -pubout 2>/dev/null | openssl pkey -pubin -outform DER 2>/dev/null | sha256sum | awk '{print $1}')"
RETIRED_PUB="$(openssl pkey -in /app/pki/retired.key -pubout 2>/dev/null | openssl pkey -pubin -outform DER 2>/dev/null | sha256sum | awk '{print $1}')"
if [ "$CERT_PUB" != "$EDGE_PUB" ]; then
    echo "edge.key does not match edge.crt?! aborting"; exit 1
fi
if [ "$CERT_PUB" = "$RETIRED_PUB" ]; then
    echo "unexpected: retired.key matches edge.crt"; exit 1
fi

python3 /app/mkbundle.py /app/pki/edge.key /app/pki/edge.crt /app/pki/bundle.pem
test -f /app/pki/bundle.pem || { echo "missing /app/pki/bundle.pem"; exit 1; }

# ---- 3. Provenance record /app/pki/bundle.meta.json ----
python3 - <<'PY'
import hashlib, json
meta = {
    "key_file": "/app/pki/edge.key",
    "cert_file": "/app/pki/edge.crt",
    "key_sha256": hashlib.sha256(open("/app/pki/edge.key", "rb").read()).hexdigest(),
    "cert_sha256": hashlib.sha256(open("/app/pki/edge.crt", "rb").read()).hexdigest(),
}
with open("/app/pki/bundle.meta.json", "w") as fh:
    json.dump(meta, fh, indent=2)
    fh.write("\n")
PY

# ---- 4. Sanity-check the bundle parses and the key matches the cert ----
openssl pkey -in /app/pki/bundle.pem -noout > /dev/null
openssl x509 -in /app/pki/bundle.pem -noout > /dev/null
BUNDLE_PUB="$(openssl pkey -in /app/pki/bundle.pem -pubout 2>/dev/null | openssl pkey -pubin -outform DER 2>/dev/null | sha256sum | awk '{print $1}')"
test "$BUNDLE_PUB" = "$CERT_PUB" || { echo "bundle key does not match cert"; exit 1; }
MODE="$(stat -c '%a' /app/pki/bundle.pem)"
test "$MODE" = "600" || { echo "bundle.pem mode is $MODE, want 600"; exit 1; }

echo "solve.sh done -> /app/mkbundle.py, /app/pki/bundle.pem, /app/pki/bundle.meta.json"

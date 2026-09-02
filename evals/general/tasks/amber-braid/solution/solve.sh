#!/bin/bash
# Oracle for amber-braid: write the deliverable tool /app/mkbundle.py, then RUN
# it on the visible spec to produce /app/bundle.pem and /app/manifest.txt.
# Never reads /tests.
set -eu

TOOL="/app/mkbundle.py"
BUNDLE="/app/bundle.pem"
MANIFEST="/app/manifest.txt"

cat > "$TOOL" <<'PY'
#!/usr/bin/env python3
"""Amber Braid bundle mint.

    python3 mkbundle.py <spec_file> <bundle_out> <manifest_out>

Reads a key=value spec, mints a fresh private key + matching self-signed
certificate with the openssl CLI, and writes a combined PEM bundle (private
key block first, certificate block second, mode 0600) plus a fingerprint
manifest.
"""
import hashlib
import os
import subprocess
import sys
import tempfile


def parse_spec(path):
    spec = {}
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            k, _, v = line.partition("=")
            spec[k.strip()] = v.strip()
    return spec


def openssl(args):
    r = subprocess.run(["openssl"] + args, capture_output=True)
    if r.returncode != 0:
        raise RuntimeError("openssl %s failed: %s"
                           % (" ".join(args), r.stderr.decode("utf-8", "replace")[:400]))
    return r.stdout


def pem_block(pem, tag):
    begin = "-----BEGIN %s-----" % tag
    end = "-----END %s-----" % tag
    return pem[pem.index(begin): pem.index(end) + len(end)] + "\n"


def main():
    spec_path, bundle_out, manifest_out = sys.argv[1], sys.argv[2], sys.argv[3]
    spec = parse_spec(spec_path)
    ktype = spec["key_type"].upper()

    with tempfile.TemporaryDirectory() as td:
        key = os.path.join(td, "key.pem")
        cert = os.path.join(td, "cert.pem")

        if ktype == "RSA":
            bits = int(spec["key_bits"])
            openssl(["genpkey", "-algorithm", "RSA",
                     "-pkeyopt", "rsa_keygen_bits:%d" % bits, "-out", key])
        elif ktype == "EC":
            curve = spec["curve"]
            openssl(["genpkey", "-algorithm", "EC",
                     "-pkeyopt", "ec_paramgen_curve:%s" % curve, "-out", key])
        else:
            raise SystemExit("unsupported key_type %r" % ktype)

        subject = "/C=%s/O=%s/CN=%s" % (spec["country"], spec["organization"],
                                        spec["common_name"])
        openssl(["req", "-new", "-x509", "-key", key, "-out", cert,
                 "-days", str(int(spec["validity_days"])), "-subj", subject])

        with open(key, "r", encoding="utf-8") as fh:
            key_pem = fh.read()
        with open(cert, "r", encoding="utf-8") as fh:
            cert_pem = fh.read()

        # Combined bundle: PRIVATE KEY block first, CERTIFICATE block second.
        with open(bundle_out, "w", encoding="utf-8") as fh:
            fh.write(pem_block(key_pem, "PRIVATE KEY"))
            fh.write(pem_block(cert_pem, "CERTIFICATE"))
        os.chmod(bundle_out, 0o600)

        cert_der = openssl(["x509", "-in", cert, "-outform", "DER"])
        spki_der = openssl(["pkey", "-in", key, "-pubout", "-outform", "DER"])
        with open(manifest_out, "w", encoding="utf-8") as fh:
            fh.write("cert_fingerprint_sha256=%s\n"
                     % hashlib.sha256(cert_der).hexdigest())
            fh.write("pubkey_fingerprint_sha256=%s\n"
                     % hashlib.sha256(spki_der).hexdigest())
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY
chmod +x "$TOOL"

python3 "$TOOL" /app/provision/spec.env "$BUNDLE" "$MANIFEST"

echo "solve.sh done -> $TOOL, $BUNDLE, $MANIFEST"
ls -l "$TOOL" "$BUNDLE" "$MANIFEST"

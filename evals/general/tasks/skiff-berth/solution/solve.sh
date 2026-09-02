#!/bin/bash
# Oracle for skiff-berth: write the hash generator, write the idempotent
# provisioning script, then RUN provisioning to produce /app/credentials.json.
# Never reads /tests.
set -eu

cat > /app/hashgen.py <<'PY'
#!/usr/bin/env python3
"""Generate a sha512-crypt hash record for a secret.

Usage: python3 hashgen.py <secret> <out_json>
"""
import crypt
import json
import sys


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: hashgen.py <secret> <out_json>")
    secret, out_path = sys.argv[1], sys.argv[2]
    salt = crypt.mksalt(crypt.METHOD_SHA512)
    digest = crypt.crypt(secret, salt)
    record = {"algo": "sha512_crypt", "hash": digest}
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(record, fh, indent=2)
        fh.write("\n")


if __name__ == "__main__":
    main()
PY
chmod +x /app/hashgen.py

cat > /app/provision.sh <<'SH'
#!/bin/bash
# Enable password-based authentication for the Skiff landing toll gateway.
# Idempotent: safe to re-run; never starts a server; never touches gateway.py.
set -eu

SECRET="TideRope-31Quay"
USER="harbormaster"
HASH_OUT="$(mktemp /tmp/skiff_hash.XXXXXX.json)"

python3 /app/hashgen.py "$SECRET" "$HASH_OUT"

python3 - "$USER" "$HASH_OUT" <<'PY'
import json
import sys

user, hash_path = sys.argv[1], sys.argv[2]
with open(hash_path, "r", encoding="utf-8") as fh:
    generated = json.load(fh)
credentials = {
    "enabled": True,
    "users": {
        user: {
            "algo": generated["algo"],
            "hash": generated["hash"],
        }
    },
}
with open("/app/credentials.json", "w", encoding="utf-8") as fh:
    json.dump(credentials, fh, indent=2)
    fh.write("\n")
PY

rm -f "$HASH_OUT"
echo "provision.sh: password-based authentication enabled for $USER"
SH
chmod +x /app/provision.sh

bash /app/provision.sh

echo "solve.sh done -> /app/hashgen.py, /app/provision.sh, /app/credentials.json"
ls -l /app/hashgen.py /app/provision.sh /app/credentials.json

#!/bin/bash
# Oracle for pipit-vault: write the recovery tool, then RUN it on the visible
# vault to produce /app/passcode.txt. Never reads /tests.
set -eu

TOOL="/app/recover.py"
OUT="/app/passcode.txt"

cat > "$TOOL" <<'PY'
import base64
import hashlib
import json
import os
import sys


def fail(msg):
    print("error: %s" % msg, file=sys.stderr)
    sys.exit(1)


def recover(vault_dir):
    manifest_path = os.path.join(vault_dir, "manifest.json")
    try:
        with open(manifest_path) as fh:
            manifest = json.load(fh)
    except Exception as exc:
        fail("cannot read manifest %s: %s" % (manifest_path, exc))

    order = manifest.get("order")
    if not isinstance(order, list) or not order:
        fail("manifest has no usable 'order' list")

    chunks = []
    for name in order:
        shard_path = os.path.join(vault_dir, "shards", name)
        try:
            with open(shard_path) as fh:
                token = fh.read().strip()
        except OSError as exc:
            fail("cannot read shard %s: %s" % (name, exc))
        if not token:
            fail("shard %s is empty" % name)
        try:
            chunks.append(base64.b32decode(token.upper()))
        except Exception as exc:
            fail("shard %s is not valid base32: %s" % (name, exc))

    assembled = b"".join(chunks).decode("utf-8")
    if manifest.get("reverse"):
        assembled = assembled[::-1]

    normalized = assembled.strip().lower()

    checksum_path = os.path.join(vault_dir, "checksum.txt")
    try:
        with open(checksum_path) as fh:
            expected = fh.read().strip().lower()
    except OSError as exc:
        fail("cannot read checksum: %s" % exc)

    digest = hashlib.sha256(normalized.encode("utf-8")).hexdigest()
    if digest != expected:
        fail("checksum mismatch: recovered %s but vault expects %s"
             % (digest, expected))
    return normalized


def main():
    if len(sys.argv) != 3:
        fail("usage: recover.py <vault_dir> <out_file>")
    vault_dir, out_file = sys.argv[1], sys.argv[2]
    normalized = recover(vault_dir)
    with open(out_file, "w") as fh:
        fh.write(normalized + "\n")
    print("recovered passcode (%d chars) -> %s" % (len(normalized), out_file))


if __name__ == "__main__":
    main()
PY

chmod +x "$TOOL"

python3 "$TOOL" /app/vault "$OUT"
echo "solve.sh done -> $TOOL $OUT"
ls -l "$TOOL" "$OUT"

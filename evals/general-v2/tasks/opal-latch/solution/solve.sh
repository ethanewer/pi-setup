#!/bin/bash
# Oracle for opal-latch: author the /app/restore.py deliverable (in-place
# exact reconstruction of the original tree from a chunk vault) and sanity-run
# it on a scratch COPY of the sample vault. Never reads /tests and never
# modifies /app/data.
set -euo pipefail

RESTORE="/app/restore.py"

cat > "$RESTORE" <<'PY'
import hashlib
import json
import os
import re
import shutil
import sys

HEX64 = re.compile(r"^[0-9a-f]{64}$")


def die(msg):
    sys.stderr.write("restore: %s\n" % msg)
    sys.exit(1)


def main():
    if len(sys.argv) != 2:
        sys.stderr.write("usage: restore.py <vault_dir>\n")
        return 2
    vault = sys.argv[1]
    if not os.path.isdir(vault):
        die("vault dir not found: %s" % vault)
    index_path = os.path.join(vault, "index.json")
    blobs_dir = os.path.join(vault, "blobs")
    if not os.path.isfile(index_path):
        die("missing index.json in %s" % vault)
    try:
        with open(index_path, "r", encoding="utf-8") as fh:
            index = json.load(fh)
    except (OSError, ValueError) as exc:
        die("index.json unreadable: %s" % exc)

    # ---- validate header ----
    if not isinstance(index, dict):
        die("index.json must be an object")
    if index.get("version") != 1:
        die("unsupported version: %r" % index.get("version"))
    chunk_size = index.get("chunk_size")
    if not isinstance(chunk_size, int) or isinstance(chunk_size, bool) or chunk_size <= 0:
        die("bad chunk_size: %r" % (chunk_size,))
    if index.get("digest") != "sha256":
        die("unsupported digest: %r" % index.get("digest"))
    entries = index.get("entries")
    if not isinstance(entries, list):
        die("entries must be a list")

    # ---- validate entries and paths before touching the tree ----
    for ent in entries:
        if not isinstance(ent, dict):
            die("entry must be an object: %r" % (ent,))
        path = ent.get("path")
        size = ent.get("size")
        chunks = ent.get("chunks")
        if not isinstance(path, str) or not path or path.startswith("/") \
                or path.endswith("/") or "\\" in path or "\x00" in path:
            die("bad path: %r" % (path,))
        parts = path.split("/")
        if any(p in ("", ".", "..") for p in parts):
            die("bad path components: %r" % (path,))
        if not isinstance(size, int) or isinstance(size, bool) or size < 0:
            die("bad size for %r: %r" % (path, size))
        if not isinstance(chunks, list):
            die("bad chunks for %r" % (path,))
        for h in chunks:
            if not isinstance(h, str) or not HEX64.match(h):
                die("bad chunk hash for %r: %r" % (path, h))
        if size == 0 and chunks:
            die("empty file with chunks: %r" % (path,))
        if size > 0 and not chunks:
            die("non-empty file without chunks: %r" % (path,))

    # ---- validate blobs and assemble in memory ----
    restored = []  # (relative_path, bytes)
    for ent in entries:
        path, size, chunks = ent["path"], ent["size"], ent["chunks"]
        pieces = []
        for i, h in enumerate(chunks):
            blob = os.path.join(blobs_dir, h + ".blob")
            if not os.path.isfile(blob):
                die("missing blob for chunk %d of %r" % (i, path))
            try:
                with open(blob, "rb") as fh:
                    data = fh.read()
            except OSError as exc:
                die("unreadable blob for %r: %s" % (path, exc))
            if hashlib.sha256(data).hexdigest() != h:
                die("blob content does not match its hash for %r" % path)
            limit = chunk_size
            is_last = (i == len(chunks) - 1)
            if len(data) > limit or (not is_last and len(data) < chunk_size):
                die("blob %d of %r has bad length %d" % (i, path, len(data)))
            pieces.append(data)
        payload = b"".join(pieces)
        if len(payload) != size:
            die("assembled length %d != declared size %d for %r"
                % (len(payload), size, path))
        restored.append((path, payload))

    # ---- write the original tree ----
    for path, payload in restored:
        full = os.path.join(vault, path)
        parent = os.path.dirname(full)
        if parent:
            os.makedirs(parent, exist_ok=True)
        with open(full, "wb") as fh:
            fh.write(payload)

    # ---- only now remove the vault artifacts ----
    if os.path.isdir(blobs_dir):
        shutil.rmtree(blobs_dir)
    if os.path.isfile(index_path):
        os.remove(index_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY
chmod +x "$RESTORE"

# ---- sanity: restore a scratch COPY of the sample vault -------------------
tmp=$(mktemp -d)
cp -a /app/data "$tmp/vault"
python3 "$RESTORE" "$tmp/vault"
[ -e "$tmp/vault/blobs" ] && { echo "blobs/ survived restore" >&2; exit 1; }
[ -e "$tmp/vault/index.json" ] && { echo "index.json survived restore" >&2; exit 1; }
[ -f "$tmp/vault/alpha/report.txt" ] || { echo "expected file missing after restore" >&2; exit 1; }
[ -f "$tmp/vault/empty.lock" ] || { echo "empty file missing after restore" >&2; exit 1; }
[ "$(wc -c < "$tmp/vault/data.bin")" -eq 192 ] || { echo "data.bin wrong size" >&2; exit 1; }
rm -rf "$tmp"

echo "solve.sh done -> $RESTORE"
ls -l "$RESTORE"

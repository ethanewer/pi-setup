#!/bin/bash
# Oracle for cobalt-crate: write the unpacker tool, run it on the visible
# store to produce /app/unpacked. Never reads /tests.
set -eu

TOOL="/app/unpack.py"
OUT="/app/unpacked"

cat > "$TOOL" <<'PY'
#!/usr/bin/env python3
"""cratepack unpacker: reconstruct the original tree from a crate store.

Validates the entire manifest and all chunk data first; writes nothing unless
everything checks out. Then materializes the exact original tree."""
import argparse
import hashlib
import json
import os
import sys


def fail(msg):
    print("error: %s" % msg, file=sys.stderr)
    sys.exit(1)


def valid_relpath(p):
    if not isinstance(p, str) or not p:
        return False
    if p.startswith("/") or "\\" in p or p.endswith("/"):
        return False
    parts = p.split("/")
    return all(part not in ("", ".", "..") for part in parts)


def is_u64(v):
    return isinstance(v, int) and not isinstance(v, bool) and 0 <= v


def hex64(v):
    return (isinstance(v, str) and len(v) == 64
            and all(c in "0123456789abcdef" for c in v))


def main():
    ap = argparse.ArgumentParser(description="unpack a cratepack store")
    ap.add_argument("--store", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    man_path = os.path.join(args.store, "manifest.json")
    try:
        with open(man_path, "r", encoding="utf-8") as fh:
            man = json.load(fh)
    except (OSError, ValueError) as exc:
        fail("cannot read manifest: %s" % exc)
    if not isinstance(man, dict) or man.get("format") != "crate-v1":
        fail("unsupported crate format")
    nbuckets = man.get("buckets")
    if not is_u64(nbuckets) or nbuckets < 1 or nbuckets > 4096:
        fail("bad bucket count")
    chunk_size = man.get("chunk_size")
    if not is_u64(chunk_size) or chunk_size < 1:
        fail("bad chunk_size")
    files = man.get("files")
    if not isinstance(files, list):
        fail("manifest.files must be a list")

    # load bucket blobs
    blobs = []
    for i in range(nbuckets):
        bpath = os.path.join(args.store, "bucket-%d.bin" % i)
        try:
            with open(bpath, "rb") as fh:
                blobs.append(fh.read())
        except OSError as exc:
            fail("missing bucket blob %d: %s" % (i, exc))

    # validate everything; assemble in memory before touching the disk
    seen = set()
    rebuilt = []
    for entry in files:
        if not isinstance(entry, dict):
            fail("file entry is not an object")
        path = entry.get("path")
        if not valid_relpath(path):
            fail("unsafe or invalid path: %r" % (path,))
        if path in seen:
            fail("duplicate path: %s" % path)
        seen.add(path)
        size = entry.get("size")
        if not is_u64(size):
            fail("bad size for %s" % path)
        want_sha = entry.get("sha256")
        if not hex64(want_sha):
            fail("bad sha256 for %s" % path)
        chunks = entry.get("chunks")
        if not isinstance(chunks, list):
            fail("bad chunks for %s" % path)
        pieces = []
        for ch in chunks:
            if not isinstance(ch, dict):
                fail("bad chunk record for %s" % path)
            b, off, ln = ch.get("bucket"), ch.get("offset"), ch.get("length")
            if not (is_u64(b) and b < nbuckets and is_u64(off) and is_u64(ln)):
                fail("bad chunk fields for %s" % path)
            blob = blobs[b]
            if off + ln > len(blob):
                fail("chunk out of range for %s" % path)
            pieces.append(blob[off:off + ln])
        data = b"".join(pieces)
        if len(data) != size:
            fail("size mismatch for %s (%d != %d)" % (path, len(data), size))
        if hashlib.sha256(data).hexdigest() != want_sha:
            fail("sha256 mismatch for %s" % path)
        rebuilt.append((path, data))

    # all validated: materialize the tree
    for path, data in rebuilt:
        dest = os.path.join(args.out, *path.split("/"))
        parent = os.path.dirname(dest)
        if parent:
            os.makedirs(parent, exist_ok=True)
        with open(dest, "wb") as fh:
            fh.write(data)

    print("UNPACKED %d" % len(rebuilt))


if __name__ == "__main__":
    main()
PY
chmod +x "$TOOL"

rm -rf "$OUT"
python3 "$TOOL" --store /app/store --out "$OUT"
find "$OUT" -type f | sort

echo "solve.sh done -> $TOOL and $OUT"

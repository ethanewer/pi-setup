#!/bin/bash
# Real oracle for maple-vellum: write the reassembler deliverable, then RUN it
# on the shipped /app/store to produce /app/restored. Never reads /tests.
set -eu

REASSEMBLER="/app/reassemble.py"
RESTORED="/app/restored"

# ---- 1. The deliverable program (this IS the work, not a canned answer).
cat > "$REASSEMBLER" <<'PY'
#!/usr/bin/env python3
"""Reassemble a resharded (chunked + deduplicated) store back into the
exact original directory tree.

Usage:
    python3 reassemble.py --store <store_dir> --out <out_dir>
"""
import argparse
import hashlib
import json
import os
import sys


def die(msg):
    print("reassemble error: %s" % msg, file=sys.stderr)
    sys.exit(1)


def load_manifest(store):
    path = os.path.join(store, "manifest.json")
    if not os.path.isfile(path):
        die("manifest.json not found in store %r" % store)
    try:
        with open(path, "r", encoding="utf-8") as fh:
            m = json.load(fh)
    except (OSError, ValueError) as exc:
        die("manifest unreadable/invalid JSON: %s" % exc)
    if not isinstance(m, dict):
        die("manifest must be a JSON object")
    if m.get("version") != 1:
        die("unsupported manifest version %r" % (m.get("version"),))
    if m.get("hash") != "sha256":
        die("unsupported hash %r (only sha256)" % (m.get("hash"),))
    dirs = m.get("dirs")
    files = m.get("files")
    if not isinstance(dirs, list) or not all(isinstance(d, str) for d in dirs):
        die("manifest 'dirs' must be a list of strings")
    if not isinstance(files, dict):
        die("manifest 'files' must be an object")
    for rel, info in files.items():
        if not isinstance(rel, str) or not isinstance(info, dict):
            die("bad 'files' entry %r" % (rel,))
        size = info.get("size")
        chunks = info.get("chunks")
        if not isinstance(size, int) or isinstance(size, bool) or size < 0:
            die("bad size for %r" % rel)
        if (not isinstance(chunks, list)
                or not all(isinstance(c, str) and len(c) == 64 for c in chunks)):
            die("bad chunks list for %r" % rel)
        for part in rel.replace("\\", "/").split("/"):
            if part in ("", ".", ".."):
                die("unsafe path component in %r" % rel)
    return m


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--store", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    store = args.store
    if not os.path.isdir(store):
        die("store directory %r does not exist" % store)
    manifest = load_manifest(store)
    files = manifest["files"]

    # Pass 1: load and verify every distinct blob once.
    blobs = {}
    for rel in files:
        for digest in files[rel]["chunks"]:
            if digest in blobs:
                continue
            if digest != digest.lower() or any(
                    c not in "0123456789abcdef" for c in digest):
                die("malformed digest %r" % digest)
            bpath = os.path.join(store, "blobs", digest[:2], digest)
            if not os.path.isfile(bpath):
                die("missing blob %s" % digest)
            try:
                with open(bpath, "rb") as fh:
                    data = fh.read()
            except OSError as exc:
                die("cannot read blob %s: %s" % (digest, exc))
            if hashlib.sha256(data).hexdigest() != digest:
                die("blob %s does not hash to its digest (corrupted store)"
                    % digest)
            blobs[digest] = data

    # Pass 2: write the tree.
    out = args.out
    os.makedirs(out, exist_ok=True)
    for d in manifest["dirs"]:
        if d.replace("\\", "/").split("/")[0] in ("", ".", ".."):
            die("unsafe directory entry %r" % d)
        os.makedirs(os.path.join(out, *d.split("/")), exist_ok=True)
    for rel in sorted(files):
        info = files[rel]
        data = b"".join(blobs[d] for d in info["chunks"])
        if len(data) != info["size"]:
            die("size mismatch for %r: reassembled %d bytes, manifest says %d"
                % (rel, len(data), info["size"]))
        dest = os.path.join(out, *rel.split("/"))
        os.makedirs(os.path.dirname(dest) or ".", exist_ok=True)
        with open(dest, "wb") as fh:
            fh.write(data)

    print("RESTORED %d files, %d dirs from %s"
          % (len(files), len(manifest["dirs"]), store))


if __name__ == "__main__":
    main()
PY
chmod +x "$REASSEMBLER"

# ---- 2. Run the produced program on the shipped store -> /app/restored.
rm -rf "$RESTORED"
python3 "$REASSEMBLER" --store /app/store --out "$RESTORED"

# ---- 3. Self-check: restored tree must satisfy the manifest exactly.
python3 - <<'PY'
import hashlib, json, os, sys

m = json.load(open('/app/store/manifest.json'))
out = '/app/restored'
bad = []
for d in m['dirs']:
    if not os.path.isdir(os.path.join(out, *d.split('/'))):
        bad.append('missing dir ' + d)
for rel, info in m['files'].items():
    p = os.path.join(out, *rel.split('/'))
    if not os.path.isfile(p):
        bad.append('missing file ' + rel)
        continue
    data = open(p, 'rb').read()
    if len(data) != info['size']:
        bad.append('size mismatch ' + rel)
    if hashlib.sha256(data).hexdigest() != hashlib.sha256(
            b''.join(open('/app/store/blobs/%s/%s' % (c[:2], c), 'rb').read()
                     for c in info['chunks'])).hexdigest():
        bad.append('content mismatch ' + rel)
if bad:
    print('ORACLE SELF-CHECK FAILURES:', bad)
    sys.exit(1)
print('ORACLE SELF-CHECK OK: %d files, %d dirs restored exactly'
      % (len(m['files']), len(m['dirs'])))
PY

echo "solve.sh done -> $REASSEMBLER and $RESTORED"
ls -l "$REASSEMBLER"
ls "$RESTORED"

#!/usr/bin/env python3
"""Build a complete offline mirror from a scattered upstream artifact cache.

Usage:
    python3 build_mirror.py <upstream_dir> <mirror_dir>

Reads manifest.json from the upstream tree, verifies every listed artifact's
existence and sha256, then copies each to <mirror_dir> under its canonical
filename. Any missing file or digest mismatch is a hard failure: exit nonzero
and never leave a complete mirror behind.
"""
import hashlib
import json
import os
import shutil
import sys
import tempfile

# logical artifact name -> canonical mirrored filename
CANONICAL = {
    "config": "config.json",
    "weights": "weights.npz",
    "vocab": "vocab.json",
    "merges": "merges.txt",
    "tokenizer_config": "tokenizer_config.json",
    "special_tokens_map": "special_tokens_map.json",
}


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def main(argv):
    if len(argv) != 3:
        print("usage: build_mirror.py <upstream_dir> <mirror_dir>", file=sys.stderr)
        return 2
    upstream, mirror = argv[1], argv[2]

    manifest_path = os.path.join(upstream, "manifest.json")
    try:
        with open(manifest_path, "r", encoding="utf-8") as fh:
            manifest = json.load(fh)
    except Exception as exc:
        print("cannot read manifest %s: %s" % (manifest_path, exc), file=sys.stderr)
        return 1

    entries = manifest.get("artifacts")
    if not isinstance(entries, list) or not entries:
        print("manifest has no artifact list", file=sys.stderr)
        return 1

    # verify + stage everything into a temp dir first: only a fully verified
    # set is ever moved into place, so a failure cannot leave a complete mirror.
    try:
        staging = tempfile.mkdtemp(prefix="mirror_build_")
        for entry in entries:
            name = entry.get("name")
            rel = entry.get("path")
            want = entry.get("sha256")
            if name not in CANONICAL:
                print("unknown artifact name %r" % name, file=sys.stderr)
                raise SystemExit(1)
            src = os.path.join(upstream, rel)
            if not os.path.isfile(src):
                print("missing source file for %r: %s" % (name, src), file=sys.stderr)
                raise SystemExit(1)
            got = sha256_file(src)
            if want is None or got != want:
                print("sha256 mismatch for %r (%s): expected %s, got %s"
                      % (name, src, want, got), file=sys.stderr)
                raise SystemExit(1)
            dst = os.path.join(staging, CANONICAL[name])
            shutil.copyfile(src, dst)
    except SystemExit:
        shutil.rmtree(staging, ignore_errors=True)
        raise
    except Exception as exc:
        shutil.rmtree(staging, ignore_errors=True)
        print("mirror build failed: %s" % exc, file=sys.stderr)
        return 1

    # success: publish the staged set
    if os.path.isdir(mirror):
        for f in CANONICAL.values():
            p = os.path.join(mirror, f)
            if os.path.exists(p):
                os.remove(p)
    else:
        os.makedirs(mirror, exist_ok=True)
    for f in CANONICAL.values():
        os.replace(os.path.join(staging, f), os.path.join(mirror, f))
    shutil.rmtree(staging, ignore_errors=True)

    print("mirror complete: %s (%d artifacts)" % (mirror, len(CANONICAL)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

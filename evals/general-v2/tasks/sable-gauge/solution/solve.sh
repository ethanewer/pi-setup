#!/bin/bash
# Real oracle for sable-gauge: write the reproducible packer, then RUN it on the
# shipped seed tree to produce /app/bundle.tar and /app/bundle.sha256.
# Never reads /tests.
set -eu

PACKER="/app/pack.py"
TAR="/app/bundle.tar"
DIGEST="/app/bundle.sha256"

cat > "$PACKER" <<'PY'
#!/usr/bin/env python3
"""Reproducible tar packer: byte-identical output for identical input trees."""
import hashlib
import os
import sys
import tarfile


def collect(in_dir):
    rels = []
    for root, dirs, files in os.walk(in_dir):
        for name in dirs + files:
            full = os.path.join(root, name)
            if os.path.islink(full) or not (os.path.isdir(full) or os.path.isfile(full)):
                continue
            rels.append(os.path.relpath(full, in_dir).replace(os.sep, "/"))
    # sort by raw UTF-8 bytes: no locale collation anywhere
    rels.sort(key=lambda r: r.encode("utf-8"))
    return rels


def pack(in_dir, out_tar):
    rels = collect(in_dir)
    with tarfile.open(out_tar, "w", format=tarfile.USTAR_FORMAT) as tf:
        for rel in rels:
            full = os.path.join(in_dir, rel)
            ti = tarfile.TarInfo(rel)
            ti.uid = 0
            ti.gid = 0
            ti.uname = ""
            ti.gname = ""
            ti.mtime = 0
            if os.path.isdir(full):
                ti.type = tarfile.DIRTYPE
                ti.mode = 0o755
                ti.size = 0
                tf.addfile(ti)
            else:
                ti.type = tarfile.REGTYPE
                ti.mode = 0o644
                ti.size = os.path.getsize(full)
                with open(full, "rb") as fh:
                    tf.addfile(ti, fh)
    return rels


def main():
    if len(sys.argv) != 4:
        print("usage: pack.py <in_dir> <out_tar> <out_digest>", file=sys.stderr)
        return 2
    in_dir, out_tar, out_digest = sys.argv[1], sys.argv[2], sys.argv[3]
    pack(in_dir, out_tar)
    h = hashlib.sha256()
    with open(out_tar, "rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    with open(out_digest, "w") as fh:
        fh.write(h.hexdigest() + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY

chmod +x "$PACKER"

python3 "$PACKER" /app/seed_tree "$TAR" "$DIGEST"

echo "solve.sh done -> $PACKER, $TAR, $DIGEST"
ls -l "$PACKER" "$TAR" "$DIGEST"

#!/usr/bin/env python3
"""Ridgeline tool 2 - reshard a tree into dirs capped by item count and byte budget."""
import os, sys, shutil


def mangle(rel: str) -> str:
    # '/' -> '__' keeps names collision-free across the whole tree.
    return rel.replace(os.sep, "__")


def main(argv):
    if len(argv) != 5:
        print("usage: reshard.py <in_dir> <out_dir> <max_items> <max_bytes>")
        return 2
    in_dir, out_dir = argv[1], argv[2]
    try:
        max_items = int(argv[3])
        max_bytes = int(argv[4])
    except ValueError:
        print("error: max_items and max_bytes must be integers")
        return 2
    if max_items < 1 or max_bytes < 1:
        print("error: max_items and max_bytes must be >= 1")
        return 2

    # gather regular files, deterministic order
    rels = []
    for dirpath, dirnames, filenames in os.walk(in_dir):
        for fn in filenames:
            full = os.path.join(dirpath, fn)
            if os.path.isfile(full):
                rels.append(os.path.relpath(full, in_dir))
    rels.sort()

    # build items: whole file or chunks
    items = []  # list of (name, bytes)
    for rel in rels:
        with open(os.path.join(in_dir, rel), "rb") as f:
            data = f.read()
        if len(data) <= max_bytes:
            items.append((mangle(rel), data))
        else:
            base = mangle(rel)
            i = 0
            for off in range(0, len(data), max_bytes):
                items.append(("%s.part_%03d" % (base, i), data[off:off + max_bytes]))
                i += 1

    if os.path.exists(out_dir):
        shutil.rmtree(out_dir)
    os.makedirs(out_dir)
    for start in range(0, len(items), max_items):
        shard = os.path.join(out_dir, "shard_%04d" % start)
        os.makedirs(shard, exist_ok=True)
        for name, chunk in items[start:start + max_items]:
            with open(os.path.join(shard, name), "wb") as f:
                f.write(chunk)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
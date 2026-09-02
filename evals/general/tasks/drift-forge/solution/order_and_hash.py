#!/usr/bin/env python3
"""Ridgeline tool 3 - deterministic manifest + reproducible archive."""

import os, sys, json, hashlib, struct


def sorted_rel_paths(root: str):
    res = []
    for dirpath, dirnames, filenames in os.walk(root):
        for fn in filenames:
            full = os.path.join(dirpath, fn)
            if os.path.isfile(full):
                res.append(os.path.relpath(full, root))
    res.sort(key=lambda p: p.encode("utf-8"))
    return res


def sha256_of_data(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main(argv):
    if len(argv) != 4 or argv[1] not in ("manifest", "bundle"):
        print("usage: order_and_hash.py (manifest|bundle) <in_dir> <out>")
        return 2
    mode, in_dir, out_path = argv[1], argv[2], argv[3]
    rels = sorted_rel_paths(in_dir)

    if mode == "manifest":
        entries = []
        for rel in rels:
            with open(os.path.join(in_dir, rel), "rb") as f:
                data = f.read()
            entries.append({"path": rel, "size": len(data), "sha256": sha256_of_data(data)})
        doc = json.dumps({"entries": entries}, ensure_ascii=True)
        with open(out_path, "w") as f:
            f.write(doc + "\n")
    else:
        with open(out_path, "wb") as f:
            f.write(b"DRIFT-FM-01\n")
            for rel in rels:
                pb = rel.encode("utf-8")
                with open(os.path.join(in_dir, rel), "rb") as g:
                    data = g.read()
                f.write(struct.pack(">I", len(pb)))
                f.write(pb)
                f.write(struct.pack(">Q", len(data)))
                f.write(data)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
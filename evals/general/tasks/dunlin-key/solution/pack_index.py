#!/usr/bin/env python3
"""Oracle for dunlin-key: deterministic firmware bundle packer.

index <in_dir> <out_json> : sorted member index with sizes + sha256
pack  <in_dir> <out_zip>  : byte-reproducible ZIP (STORED, fixed timestamps,
                            no host metadata). Standard library only."""
import hashlib
import json
import os
import sys
import zipfile

FORMAT = "fw-bundle-index-1"


def sorted_paths(root):
    out = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        for fn in filenames:
            full = os.path.join(dirpath, fn)
            if os.path.islink(full) or not os.path.isfile(full):
                continue
            out.append(os.path.relpath(full, root))
    return sorted(out)


def cmd_index(indir, out_json):
    entries = []
    for rel in sorted_paths(indir):
        with open(os.path.join(indir, rel), "rb") as fh:
            data = fh.read()
        entries.append(
            {"path": rel, "size": len(data), "sha256": hashlib.sha256(data).hexdigest()}
        )
    obj = {"format": FORMAT, "entries": entries}
    with open(out_json, "w", encoding="utf-8") as fh:
        json.dump(obj, fh, indent=2, sort_keys=True, ensure_ascii=True)
        fh.write("\n")


def cmd_pack(indir, out_zip):
    with zipfile.ZipFile(out_zip, "w") as zf:
        for rel in sorted_paths(indir):
            with open(os.path.join(indir, rel), "rb") as fh:
                data = fh.read()
            info = zipfile.ZipInfo(filename=rel, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_STORED
            zf.writestr(info, data)


def main(argv):
    if len(argv) != 4 or argv[1] not in ("index", "pack"):
        print(
            "usage: pack_index.py index <in_dir> <out_json> | "
            "pack <in_dir> <out_zip>",
            file=sys.stderr,
        )
        return 2
    if argv[1] == "index":
        cmd_index(argv[2], argv[3])
    else:
        cmd_pack(argv[2], argv[3])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

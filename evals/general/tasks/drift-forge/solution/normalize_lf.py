#!/usr/bin/env python3
"""Ridgeline tool 1 - normalise text line endings to LF, leave binary identical."""
import os, sys, shutil


def is_binary(data: bytes) -> bool:
    return b"\x00" in data


def normalize_text(data: bytes) -> bytes:
    return data.replace(b"\r\n", b"\n").replace(b"\x0d", b"\n")


def main(argv):
    if len(argv) != 3:
        print("usage: normalize_lf.py <in_dir> <out_dir>")
        return 2
    src, dst = argv[1], argv[2]
    src_abs, dst_abs = os.path.abspath(src), os.path.abspath(dst)
    if dst_abs.startswith(src_abs + os.sep):
        print("error: out_dir must not be inside in_dir")
        return 2
    if os.path.exists(dst):
        shutil.rmtree(dst)
    os.makedirs(dst)
    for dirpath, dirnames, filenames in os.walk(src):
        for fn in filenames:
            full = os.path.join(dirpath, fn)
            if not os.path.isfile(full):
                continue
            rel = os.path.relpath(full, src)
            outp = os.path.join(dst, rel)
            os.makedirs(os.path.dirname(outp), exist_ok=True)
            with open(full, "rb") as f:
                data = f.read()
            out_data = data if is_binary(data) else normalize_text(data)
            with open(outp, "wb") as f:
                f.write(out_data)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
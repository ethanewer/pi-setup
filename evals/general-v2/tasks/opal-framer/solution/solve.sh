#!/bin/bash
# Oracle for opal-framer: write the framer.py program (this IS the work), then
# RUN it on the visible fixture to produce /app/payload and /app/reassembled.bin.
# Never reads /tests.
set -eu

FRAMER="/app/framer.py"

# ---- 1. Write the deliverable program.
cat > "$FRAMER" <<'PY'
import hashlib
import json
import os
import sys


def die(msg, code=2):
    sys.stderr.write("framer: %s\n" % msg)
    sys.exit(code)


def sha256(b):
    return hashlib.sha256(b).hexdigest()


def parse_cap(raw):
    try:
        cap = int(raw, 10)
    except (TypeError, ValueError):
        die("CAP must be a positive integer, got %r" % raw)
    if cap < 1:
        die("CAP must be >= 1, got %d" % cap)
    return cap


def cmd_pack(argv):
    if len(argv) != 3:
        die("usage: framer.py pack INPUT OUT_DIR CAP")
    inp, out_dir, cap_raw = argv
    if not (os.path.isfile(inp)):
        die("no such input file: %s" % inp)
    cap = parse_cap(cap_raw)
    with open(inp, "rb") as fh:
        data = fh.read()
    size = len(data)
    n = (size + cap - 1) // cap  # 0 for empty input
    os.makedirs(out_dir, exist_ok=True)
    parts = []
    for i in range(n):
        lo = i * cap
        chunk = data[lo:lo + cap]
        name = "frame_%05d.bin" % i
        with open(os.path.join(out_dir, name), "wb") as fh:
            fh.write(chunk)
        parts.append({
            "name": name,
            "offset": lo,
            "length": len(chunk),
            "sha256": sha256(chunk),
        })
    manifest = {
        "input": os.path.basename(inp),
        "size": size,
        "cap": cap,
        "frames": n,
        "sha256": sha256(data),
        "parts": parts,
    }
    with open(os.path.join(out_dir, "index.json"), "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=2, sort_keys=True)
        fh.write("\n")


def cmd_unpack(argv):
    if len(argv) != 2:
        die("usage: framer.py unpack OUT_DIR OUTPUT")
    out_dir, output = argv
    idx_path = os.path.join(out_dir, "index.json")
    if not os.path.isfile(idx_path):
        die("missing manifest: %s" % idx_path)
    try:
        with open(idx_path, "r", encoding="utf-8") as fh:
            manifest = json.load(fh)
        size = int(manifest["size"])
        total_sha = str(manifest["sha256"])
        parts = list(manifest["parts"])
    except Exception as exc:
        die("malformed manifest: %s" % exc)
    chunks = []
    for part in parts:
        try:
            name = str(part["name"])
            length = int(part["length"])
            part_sha = str(part["sha256"])
        except Exception as exc:
            die("malformed part entry: %s" % exc)
        path = os.path.join(out_dir, name)
        if not os.path.isfile(path):
            die("corrupt frame %s: missing" % name)
        with open(path, "rb") as fh:
            chunk = fh.read()
        if len(chunk) != length or sha256(chunk) != part_sha:
            die("corrupt frame %s: digest/length mismatch" % name)
        chunks.append(chunk)
    data = b"".join(chunks)
    if len(data) != size or sha256(data) != total_sha:
        die("corrupt frame set: assembled digest/size mismatch")
    with open(output, "wb") as fh:
        fh.write(data)


def main():
    if len(sys.argv) < 2:
        die("usage: framer.py pack|unpack ...")
    cmd = sys.argv[1]
    if cmd == "pack":
        cmd_pack(sys.argv[2:])
    elif cmd == "unpack":
        cmd_unpack(sys.argv[2:])
    else:
        die("unknown command: %s" % cmd)


if __name__ == "__main__":
    main()
PY

chmod +x "$FRAMER"

# ---- 2. Run the produced program on the visible fixture to generate outputs.
python3 "$FRAMER" pack /app/image.bin /app/payload 1000
python3 "$FRAMER" unpack /app/payload /app/reassembled.bin

cmp /app/image.bin /app/reassembled.bin

test -f /app/payload/index.json
echo "solve.sh done -> $FRAMER, /app/payload/index.json, /app/reassembled.bin"
ls -l /app/payload/index.json /app/reassembled.bin

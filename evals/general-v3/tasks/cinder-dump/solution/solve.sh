#!/bin/bash
# Real oracle for cinder-dump: write the generic hexdump reassembler, then RUN
# it on the visible dumps to produce /app/recovered.bin, then execute the
# recovered artifact to capture /app/recovered_out.txt. Never reads /tests.
set -eu

cat > /app/solve.py <<'PY'
"""Reassemble a binary image from hexdump -C style fragment files."""
import os
import re
import sys

RE_DATA = re.compile(r"^([0-9a-f]{8})  ")
RE_OFF = re.compile(r"^([0-9a-f]{8})$")


def parse_fragment(path, image):
    star = False
    prev_off = None
    lastrow = None
    for raw in open(path, "r", encoding="utf-8"):
        ln = raw.rstrip("\n")
        if ln == "*":
            star = True
            continue
        m_off = RE_OFF.match(ln)
        if m_off:
            if star and lastrow:
                end = int(m_off.group(1), 16)
                for k in range(end - prev_off):
                    image[prev_off + k] = lastrow[k % len(lastrow)]
            star = False
            continue
        m = RE_DATA.match(ln)
        if not m:
            continue  # tolerate blank/stray lines
        off = int(m.group(1), 16)
        if star and lastrow:
            # expand the repeat run up to (not including) this row's offset
            for k in range(off - prev_off):
                image[prev_off + k] = lastrow[k % len(lastrow)]
        star = False
        bs = [int(t, 16) for t in ln[10:58].split()
              if re.fullmatch(r"[0-9a-f]{2}", t)]
        for k, b in enumerate(bs):
            image[off + k] = b
        prev_off = off
        lastrow = bs


def reassemble(dumps_dir):
    manifest = os.path.join(dumps_dir, "manifest.txt")
    names = [l.strip() for l in open(manifest, "r", encoding="utf-8")
             if l.strip()]
    image = {}
    for name in names:
        parse_fragment(os.path.join(dumps_dir, name), image)
    if not image:
        raise ValueError("no data recovered from fragments")
    size = max(image) + 1
    return bytes(image.get(i, 0) for i in range(size))


def main(argv):
    if len(argv) != 3:
        print("usage: solve.py <dumps_dir> <out_bin>", file=sys.stderr)
        return 2
    data = reassemble(argv[1])
    with open(argv[2], "wb") as f:
        f.write(data)
    os.chmod(argv[2], 0o755)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
PY

chmod +x /app/solve.py

python3 /app/solve.py /app/dumps /app/recovered.bin
chmod +x /app/recovered.bin
/app/recovered.bin > /app/recovered_out.txt

echo "solve.sh done"
ls -l /app/solve.py /app/recovered.bin /app/recovered_out.txt
cat /app/recovered_out.txt

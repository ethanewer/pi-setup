#!/bin/bash
# Real oracle for marble-hollow: write the segmenter program, then RUN it on the
# visible blob to produce the pack index and the round-trip restore.
# Never reads /tests.
set -eu

SEGMENTER="/app/segmenter.py"

# ---- 1. Write the deliverable program (this IS the work, not a canned answer).
cat > "$SEGMENTER" <<'PY'
#!/usr/bin/env python3
"""SEG/1 blob segmenter: pack under a per-file byte quota, merge back exactly."""
import hashlib
import json
import os
import re
import sys

HEADER_LEN = 83  # b"SEG\t%06d\t%06d\t" (18) + 64 hex + b"\n"
SEG_RE = re.compile(r"^SEG\t\d{6}\t\d{6}\t[0-9a-f]{64}\n$")


def die(msg):
    sys.stderr.write(msg + "\n")
    sys.exit(2)


def sha256_hex(data):
    return hashlib.sha256(data).hexdigest()


def parse_int(text):
    try:
        value = int(str(text).strip())
    except (TypeError, ValueError):
        return None
    return value


def cmd_pack(input_path, cap_raw, outdir):
    if not os.path.isfile(input_path):
        die("pack: no such file: %s" % input_path)
    cap = parse_int(cap_raw)
    if cap is None or cap <= 0:
        die("pack: invalid cap: %s" % cap_raw)
    if cap < HEADER_LEN + 1:
        die("pack: cap too small: %s" % cap_raw)

    with open(input_path, "rb") as fh:
        data = fh.read()
    size = len(data)
    payload_cap = cap - HEADER_LEN
    k = (size + payload_cap - 1) // payload_cap  # 0 for empty input

    os.makedirs(outdir, exist_ok=True)
    # Clear stale segment files from any previous pack.
    for name in os.listdir(outdir):
        if re.match(r"^seg_\d{6}\.bin$", name):
            os.remove(os.path.join(outdir, name))

    for i in range(k):
        payload = data[i * payload_cap:(i + 1) * payload_cap]
        header = ("SEG\t%06d\t%06d\t%s\n" % (i, k, sha256_hex(payload))).encode("ascii")
        with open(os.path.join(outdir, "seg_%06d.bin" % i), "wb") as fh:
            fh.write(header + payload)

    index = {
        "format": "SEG/1",
        "input": os.path.basename(input_path),
        "size": size,
        "cap": cap,
        "segments": k,
        "header_len": HEADER_LEN,
        "digest": sha256_hex(data),
    }
    with open(os.path.join(outdir, "segments.json"), "w", encoding="utf-8") as fh:
        json.dump(index, fh, indent=2, sort_keys=True)
        fh.write("\n")


def cmd_merge(outdir, output_path):
    index_path = os.path.join(outdir, "segments.json")
    try:
        with open(index_path, "r", encoding="utf-8") as fh:
            index = json.load(fh)
    except Exception:
        die("merge: no index in %s" % outdir)

    try:
        size = int(index["size"])
        k = int(index["segments"])
        digest = str(index["digest"])
        header_len = int(index.get("header_len", HEADER_LEN))
    except (KeyError, TypeError, ValueError):
        die("merge: malformed index in %s" % outdir)
    if size < 0 or k < 0 or not (digest and re.match(r"^[0-9a-f]{64}$", digest)):
        die("merge: malformed index in %s" % outdir)

    parts = []
    for i in range(k):
        seg_path = os.path.join(outdir, "seg_%06d.bin" % i)
        if not os.path.isfile(seg_path):
            die("merge: missing segment %d" % i)
        with open(seg_path, "rb") as fh:
            raw = fh.read()
        if len(raw) < header_len:
            die("merge: bad header in segment %d" % i)
        header, payload = raw[:header_len], raw[header_len:]
        header_text = header.decode("ascii", errors="strict")
        if not SEG_RE.match(header_text):
            die("merge: bad header in segment %d" % i)
        fields = header_text[:-1].split("\t")
        if int(fields[1]) != i or int(fields[2]) != k:
            die("merge: bad header in segment %d" % i)
        if sha256_hex(payload) != fields[3]:
            die("merge: digest mismatch in segment %d" % i)
        parts.append(payload)

    blob = b"".join(parts)
    if len(blob) != size:
        die("merge: size mismatch (got %d, expected %d)" % (len(blob), size))
    if sha256_hex(blob) != digest:
        die("merge: digest mismatch in output")

    tmp = output_path + ".tmp"
    with open(tmp, "wb") as fh:
        fh.write(blob)
    os.replace(tmp, output_path)


def main(argv):
    if len(argv) >= 5 and argv[1] == "pack":
        cmd_pack(argv[2], argv[3], argv[4])
    elif len(argv) >= 4 and argv[1] == "merge":
        cmd_merge(argv[2], argv[3])
    else:
        die("usage: segmenter.py pack <input> <cap> <outdir> | merge <outdir> <output>")


if __name__ == "__main__":
    main(sys.argv)
PY

chmod +x "$SEGMENTER"

# ---- 2. Visible case: pack under the gateway quota, then round-trip.
python3 "$SEGMENTER" pack /app/snapshots.blob 65536 /app/segments
python3 "$SEGMENTER" merge /app/segments /app/snapshots.restored

# Sanity: both visible-case artifacts must now exist.
test -f /app/segments/segments.json
test -f /app/snapshots.restored

echo "solve.sh done -> $SEGMENTER + /app/segments/ + /app/snapshots.restored"
ls -l /app/segments /app/snapshots.restored

#!/bin/bash
# Real oracle for pewter-hull: write the framer.py deliverable (this IS the
# work, not canned state), then RUN it on the visible fixtures to produce
# /app/frames. Never reads /tests.
set -eu

mkdir -p /app/frames

cat > /app/framer.py <<'PYEOF'
#!/usr/bin/env python3
"""Framer: fragment oversized files into telemetry frames of a bounded size.

Usage:
  framer.py split INPUT CAP OUT_DIR
  framer.py join  OUT_DIR OUTPUT
  framer.py audit OUT_DIR

Frame file layout (each frame file is at most CAP bytes):
  bytes 0..3   magic b"FRM1"
  bytes 4..7   frame index, 0-based, big-endian uint32
  bytes 8..11  total frame count K, big-endian uint32
  bytes 12..15 payload length P, big-endian uint32
  bytes 16..   payload (P bytes)

CAP must be an integer >= HEADER (16) + 1, so every frame carries at least
one payload byte. Every frame is exactly CAP bytes except the last, which
holds min(CAP, remaining) bytes.
"""

import hashlib
import json
import math
import os
import struct
import sys

MAGIC = b"FRM1"
HEADER = 16
MIN_CAP = HEADER + 1


def fail(msg, code):
    sys.stderr.write("framer: %s\n" % msg)
    sys.exit(code)


def parse_cap(text):
    try:
        cap = int(str(text).strip(), 10)
    except (ValueError, AttributeError):
        fail("cap must be an integer, got %r" % (text,), 2)
    if cap < MIN_CAP:
        fail("cap must be >= %d (16-byte header + payload), got %d"
             % (MIN_CAP, cap), 2)
    return cap


def frame_name(i):
    return "frame_%04d.frag" % i


def cmd_split(argv):
    if len(argv) != 3:
        fail("usage: framer.py split INPUT CAP OUT_DIR", 2)
    in_path, cap_text, out_dir = argv
    if not os.path.isfile(in_path):
        fail("no such file: %s" % in_path, 2)
    cap = parse_cap(cap_text)
    with open(in_path, "rb") as fh:
        data = fh.read()
    size = len(data)
    ppr = cap - HEADER
    total = int(math.ceil(size / float(ppr))) if size else 0

    os.makedirs(out_dir, exist_ok=True)
    # clear stale frames from any previous run
    for name in os.listdir(out_dir):
        if name == "manifest.json" or (name.startswith("frame_")
                                       and name.endswith(".frag")):
            os.remove(os.path.join(out_dir, name))

    frame_files = []
    frame_hashes = []
    for i in range(total):
        payload = data[i * ppr:(i + 1) * ppr]
        blob = MAGIC + struct.pack(">III", i, total, len(payload)) + payload
        fname = frame_name(i)
        with open(os.path.join(out_dir, fname), "wb") as fh:
            fh.write(blob)
        frame_files.append(fname)
        frame_hashes.append(hashlib.sha256(blob).hexdigest())

    manifest = {
        "magic": MAGIC.decode("ascii"),
        "input": os.path.basename(in_path),
        "size": size,
        "cap": cap,
        "header_size": HEADER,
        "frames": total,
        "payload_per_frame": ppr,
        "frame_files": frame_files,
        "sha256": hashlib.sha256(data).hexdigest(),
        "frame_sha256": frame_hashes,
    }
    with open(os.path.join(out_dir, "manifest.json"), "w") as fh:
        json.dump(manifest, fh, indent=2, sort_keys=True)
    print("split: %d frame(s), %d byte(s), cap %d" % (total, size, cap))


def load_manifest(out_dir):
    mpath = os.path.join(out_dir, "manifest.json")
    if not os.path.isfile(mpath):
        fail("missing manifest.json in %s" % out_dir, 3)
    try:
        with open(mpath, "r") as fh:
            m = json.load(fh)
    except ValueError as exc:
        fail("manifest.json is not valid JSON: %s" % exc, 3)
    for key in ("magic", "size", "cap", "header_size", "frames",
                "payload_per_frame", "frame_files", "sha256",
                "frame_sha256"):
        if key not in m:
            fail("manifest missing key: %s" % key, 3)
    if m["magic"] != MAGIC.decode("ascii"):
        fail("unknown magic %r" % (m["magic"],), 3)
    if m["header_size"] != HEADER:
        fail("unsupported header size %r" % (m["header_size"],), 3)
    if not isinstance(m["frame_files"], list) \
            or not isinstance(m["frame_sha256"], list) \
            or len(m["frame_files"]) != m["frames"] \
            or len(m["frame_sha256"]) != m["frames"]:
        fail("manifest frame lists inconsistent", 3)
    return m


def collect(out_dir):
    """Validate every frame; return the reassembled bytes."""
    m = load_manifest(out_dir)
    total = int(m["frames"])
    cap = int(m["cap"])
    ppr = int(m["payload_per_frame"])
    if ppr != cap - HEADER or cap < MIN_CAP:
        fail("manifest cap/payload_per_frame inconsistent", 3)
    size = int(m["size"])
    expected_frames = int(math.ceil(size / float(ppr))) if size else 0
    if total != expected_frames:
        fail("manifest frames count inconsistent with size/cap", 3)
    parts = []
    for i in range(total):
        fname = m["frame_files"][i]
        fpath = os.path.join(out_dir, fname)
        if not os.path.isfile(fpath):
            fail("missing frame file: %s" % fname, 3)
        with open(fpath, "rb") as fh:
            blob = fh.read()
        if len(blob) > cap:
            fail("frame %s is %d bytes, over cap %d" % (fname, len(blob), cap), 3)
        if len(blob) < HEADER:
            fail("frame %s truncated" % fname, 3)
        if blob[:4] != MAGIC:
            fail("frame %s has bad magic" % fname, 3)
        idx, tot, plen = struct.unpack(">III", blob[4:HEADER])
        if idx != i or tot != total:
            fail("frame %s header index/count mismatch" % fname, 3)
        if plen != len(blob) - HEADER:
            fail("frame %s payload length mismatch" % fname, 3)
        expected_plen = min(ppr, size - i * ppr)
        if plen != max(expected_plen, 0):
            fail("frame %s payload length not per framing rule" % fname, 3)
        if hashlib.sha256(blob).hexdigest() != m["frame_sha256"][i]:
            fail("frame %s failed integrity check" % fname, 3)
        parts.append(blob[HEADER:])
    data = b"".join(parts)
    if len(data) != size:
        fail("reassembled %d bytes, manifest says %d" % (len(data), size), 3)
    if hashlib.sha256(data).hexdigest() != m["sha256"]:
        fail("reassembled content failed sha256 check", 3)
    return data, m


def cmd_join(argv):
    if len(argv) != 2:
        fail("usage: framer.py join OUT_DIR OUTPUT", 2)
    out_dir, out_path = argv
    data, _m = collect(out_dir)  # verify everything before writing anything
    with open(out_path, "wb") as fh:
        fh.write(data)
    print("join: wrote %d byte(s) to %s" % (len(data), out_path))


def cmd_audit(argv):
    if len(argv) != 1:
        fail("usage: framer.py audit OUT_DIR", 2)
    _data, m = collect(argv[0])
    print("AUDIT_OK frames=%d size=%d sha=%s"
          % (m["frames"], m["size"], m["sha256"]))


def main():
    if len(sys.argv) < 2:
        fail("usage: framer.py {split|join|audit} ...", 2)
    cmd = sys.argv[1]
    handlers = {"split": cmd_split, "join": cmd_join, "audit": cmd_audit}
    if cmd not in handlers:
        fail("unknown command %r" % cmd, 2)
    handlers[cmd](sys.argv[2:])


if __name__ == "__main__":
    main()
PYEOF

chmod +x /app/framer.py

# Run the produced tool on the visible fixtures (exact command from the task).
python3 /app/framer.py split /app/uplink/payload.bin "$(cat /app/uplink/cap.txt)" /app/frames
python3 /app/framer.py audit /app/frames
rm -f /tmp/rt.bin && python3 /app/framer.py join /app/frames /tmp/rt.bin
cmp /app/uplink/payload.bin /tmp/rt.bin

echo "solve.sh done"
ls -l /app/framer.py /app/frames/manifest.json

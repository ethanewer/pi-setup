#!/bin/bash
set -eu
# pearl-scroll oracle: author the streaming edit tool, then run it for real.
mkdir -p /app
cat > /app/edit_stream.py <<'PYEOF'
"""
apply large UTF-8 text stream edits by byte offset
Usage:
    python3 edit_stream.py SOURCE EDITS OUT_TXT OUT_MANIFEST

Edit object: {"start":int,"end":int,"text":str}
  - start/end are 0-based byte offsets in the ORIGINAL source bytes.
  - [start,end) is replaced by the UTF-8 bytes of `text`.
  - edits must be non-overlapping and 0 <= start < end <= len(source).
  - empty `text` deletes the range.
On any invalid edit, prints an error to stderr and exits with status 1.
Manifest: {"sha256":"<hex>","byte_length":N}
"""
import hashlib
import json
import os
import sys

CHUNK = 1 << 20


def die(msg):
    sys.stderr.write("edit_stream: %s\n" % msg)
    sys.exit(1)


def load_edits(path, filesize):
    try:
        with open(path, "rb") as f:
            raw = f.read()
    except OSError as exc:
        die("cannot read edits file %s: %s" % (path, exc))
    try:
        data = json.loads(raw.decode("utf-8"))
    except Exception as exc:
        die("edits file is not valid JSON: %s" % exc)
    if not isinstance(data, list):
        die("edits must be a JSON array")
    parsed = []
    for it in data:
        if not isinstance(it, dict):
            die("each edit must be a JSON object")
        if set(it.keys()) != {"start", "end", "text"}:
            die("each edit must have exactly start, end, text keys")
        s, e, t = it["start"], it["end"], it["text"]
        if not isinstance(s, int) or isinstance(s, bool) or \
           not isinstance(e, int) or isinstance(e, bool) or \
           not isinstance(t, str):
            die("start/end must be integers and text must be a string")
        parsed.append((s, e, t))
    parsed.sort(key=lambda x: x[0])
    prev_end = -1
    for s, e, _ in parsed:
        if s < 0 or e <= s:
            die("edit range [%d,%d) is invalid: need 0 <= start < end" % (s, e))
        if e > filesize:
            die("edit end %d exceeds source length %d" % (e, filesize))
        if s < prev_end:
            die("edits overlap or are misordered at byte offset %d" % s)
        prev_end = e
    return parsed


def copy_segment(fin, fout, h, nbytes):
    """Copy exactly nbytes from current position, streaming, updating hash."""
    remaining = nbytes
    written = 0
    while remaining > 0:
        chunk = fin.read(min(CHUNK, remaining))
        if not chunk:
            break
        clen = len(chunk)
        fout.write(chunk)
        h.update(chunk)
        written += clen
        remaining -= clen
    return written


def run(src_path, ed_path, out_txt, out_manifest):
    try:
        filesize = os.path.getsize(src_path)
    except OSError as exc:
        die("cannot stat source %s: %s" % (src_path, exc))
    data = load_edits(ed_path, filesize)

    h = hashlib.sha256()
    total = 0
    with open(src_path, "rb") as fin, open(out_txt, "wb") as fout:
        # stream the original, replacing [start,end) for each edit
        fin.seek(0)
        pos = 0
        for s, e, text in data:
            total += copy_segment(fin, fout, h, s - pos)
            raw = text.encode("utf-8")
            fout.write(raw)
            h.update(raw)
            total += len(raw)
            fin.seek(e - s, 1)  # advance over the replaced [start,end) bytes
            pos = e
        total += copy_segment(fin, fout, h, filesize - pos)
    with open(out_manifest, "w", encoding="utf-8") as f:
        json.dump({"sha256": h.hexdigest(), "byte_length": total}, f)


if __name__ == "__main__":
    if len(sys.argv) != 5:
        die("usage: edit_stream.py SOURCE EDITS OUT_TXT OUT_MANIFEST")
    run(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4])
PYEOF
chmod +x /app/edit_stream.py
python3 /app/edit_stream.py /app/source.txt /app/edits.json /app/edited.txt /app/manifest.json

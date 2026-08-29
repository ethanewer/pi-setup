#!/bin/bash
# Gold oracle for raven-orchid ("Gryphon Relay" media-ingest pipeline).
#
# Writes the four reusable deliverable programs as REAL work products, then
# RUNS each of them against the shipped visible fixtures to produce every
# required output file in /app. It never reads /tests and never cats a
# precomputed answer.
set -eu

cd /app

# ---------------------------------------------------------------------------
# 1. ingest.py  -- fetch media from a URL list, deterministic sha256(url)
#    filenames, transcribe video content with the bundled offline ASR model,
#    and write raw + normalized transcript files.
# ---------------------------------------------------------------------------
cat > /app/ingest.py <<'PY'
#!/usr/bin/env python3
"""Gryphon Relay ingest pipeline.

Usage:  python3 /app/ingest.py <urls_file> <media_out_dir> <raw_transcript> <clean_transcript>

For every non-blank line in <urls_file> the program downloads the URL, saves
the body under <media_out_dir>/<sha256(url)>.<ext>, records it in
<media_out_dir>/manifest.json, and (for video URLs) transcribes the content
with the offline vosk model located at $VOSK_MODEL.  Each video contributes one
line to <raw_transcript>; <clean_transcript> is the normalized copy.
"""
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request

VOSK_MODEL = os.environ.get("VOSK_MODEL", "/app/vosk-model")

VIDEO_EXT = {".mp4", ".mov", ".m4v", ".webm", ".avi", ".mkv"}
IMAGE_EXT = {".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp"}
AUDIO_EXT = {".mp3", ".wav", ".m4a", ".aac", ".ogg", ".flac"}


def classify(url):
    path = urllib.parse.urlparse(url).path
    ext = os.path.splitext(os.path.basename(path))[1].lower()
    if ext in VIDEO_EXT:
        kind = "video"
    elif ext in IMAGE_EXT:
        kind = "image"
    elif ext in AUDIO_EXT:
        kind = "audio"
    else:
        kind = "other"
    return kind, ext


def sha256_bytes(b):
    return hashlib.sha256(b).hexdigest()


def sha256_url(s):
    return hashlib.sha256(s.encode("utf-8")).hexdigest()


def fetch(url):
    try:
        with urllib.request.urlopen(url, timeout=60) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as e:
        return e.code, b""
    except Exception:
        return "ERR", b""


def transcribe(video_path):
    wav = tempfile.mktemp(suffix=".wav")
    try:
        subprocess.run(
            ["ffmpeg", "-y", "-loglevel", "error", "-i", video_path,
             "-ar", "16000", "-ac", "1", "-sample_fmt", "s16", wav],
            check=True, capture_output=True,
        )
        from vosk import Model, KaldiRecognizer
        import wave
        model = Model(VOSK_MODEL)
        wf = wave.open(wav, "rb")
        rec = KaldiRecognizer(model, wf.getframerate())
        parts = []
        while True:
            data = wf.readframes(4000)
            if not data:
                break
            if rec.AcceptWaveform(data):
                t = json.loads(rec.Result())["text"].strip()
                if t:
                    parts.append(t)
        final = json.loads(rec.FinalResult())["text"].strip()
        if final:
            parts.append(final)
        return " ".join(parts)
    finally:
        if os.path.exists(wav):
            os.unlink(wav)


def normalize(text):
    lines = []
    for line in text.splitlines():
        s = re.sub(r"[^a-z0-9 ]", " ", line.lower())
        s = re.sub(r" +", " ", s).strip()
        lines.append(s)
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("urls_file")
    ap.add_argument("media_out_dir")
    ap.add_argument("raw_transcript")
    ap.add_argument("clean_transcript")
    args = ap.parse_args()

    urls = []
    with open(args.urls_file, "r", encoding="utf-8") as fh:
        for line in fh:
            u = line.strip()
            if u:
                urls.append(u)

    os.makedirs(args.media_out_dir, exist_ok=True)
    entries = []
    raw_lines = []
    for url in urls:
        status, data = fetch(url)
        kind, ext = classify(url)
        name = sha256_url(url) + ext
        entry = {
            "url": url,
            "kind": kind,
            "status": status,
            "file": name if status == 200 else "",
            "url_sha256": sha256_url(url),
            "bytes_sha256": sha256_bytes(data) if status == 200 else "",
        }
        if status == 200:
            with open(os.path.join(args.media_out_dir, name), "wb") as fh:
                fh.write(data)
        entries.append(entry)
        if kind == "video" and status == 200:
            raw_lines.append(transcribe(os.path.join(args.media_out_dir, name)))

    with open(os.path.join(args.media_out_dir, "manifest.json"), "w", encoding="utf-8") as fh:
        json.dump({"entries": entries}, fh, indent=2)

    raw = "\n".join(raw_lines)
    if raw:
        raw += "\n"
    with open(args.raw_transcript, "w", encoding="utf-8") as fh:
        fh.write(raw)
    with open(args.clean_transcript, "w", encoding="utf-8") as fh:
        fh.write(normalize(raw))


if __name__ == "__main__":
    main()
PY

# ---------------------------------------------------------------------------
# 2. stack.py  -- concatenate every TIFF frame in a directory along a new
#    leading axis (single image -> 2D, many -> 3D).
# ---------------------------------------------------------------------------
cat > /app/stack.py <<'PY'
#!/usr/bin/env python3
"""Stack TIFF frames from a directory along a new leading axis.

Usage:  python3 /app/stack.py <tif_dir> <shape_out> [stack_out.npy]

Reads every *.tif / *.tiff file in <tif_dir> (other files are ignored).  A
single frame yields a 2D array "H,W"; several frames yield a 3D array
"N,H,W".  Writes to <shape_out> one of: "H,W" | "N,H,W" | "EMPTY" | "INCOMPATIBLE".
When <stack_out.npy> is given the stacked array is saved there too.
"""
import os
import sys

import numpy as np
import tifffile


def frames_from(dirpath):
    names = sorted(
        n for n in os.listdir(dirpath)
        if n.lower().endswith((".tif", ".tiff"))
    )
    out = []
    for name in names:
        arr = tifffile.imread(os.path.join(dirpath, name))
        arr = np.asarray(arr)
        if arr.ndim == 3:
            arr = arr[0]
        out.append(arr)
    return out


def shape_str(arr):
    return ",".join(str(d) for d in arr.shape)


def main():
    if len(sys.argv) not in (3, 4):
        print("usage: stack.py <tif_dir> <shape_out> [stack_out.npy]", file=sys.stderr)
        sys.exit(2)
    tif_dir, shape_out = sys.argv[1], sys.argv[2]
    npy_out = sys.argv[3] if len(sys.argv) == 4 else None

    frames = frames_from(tif_dir)
    if not frames:
        with open(shape_out, "w") as fh:
            fh.write("EMPTY")
        return
    if len({tuple(f.shape) for f in frames}) != 1:
        with open(shape_out, "w") as fh:
            fh.write("INCOMPATIBLE")
        return

    stack = frames[0] if len(frames) == 1 else np.stack(frames, axis=0)
    with open(shape_out, "w") as fh:
        fh.write(shape_str(stack))
    if npy_out:
        np.save(npy_out, stack)


if __name__ == "__main__":
    main()
PY

# ---------------------------------------------------------------------------
# 3. peaks.py  -- per-frame top-k frequency bins in descending magnitude order.
# ---------------------------------------------------------------------------
cat > /app/peaks.py <<'PY'
#!/usr/bin/env python3
"""Per-frame top-k frequency-bin peaks.

Usage:  python3 /app/peaks.py <magnitudes.npy> <k> <out.csv>

<magnitudes.npy> is a 2D numeric array (frames x bins); a 1D array is treated
as a single frame.  For each frame the <k> bins with the largest magnitude are
written to <out.csv> in descending magnitude order, frame-by-frame.  Ties keep
the lower-numbered bin first; k<0 is clamped to 0; k above the bin count returns
every bin.  An array that cannot be read or is not 1D/2D numeric writes a single
line "ERROR".
"""
import sys

import numpy as np

HEADER = "frame,bins"


def rows_for(arr, k):
    parsed = np.load(arr, allow_pickle=False)
    if parsed.ndim == 1:
        parsed = parsed.reshape(1, -1)
    if parsed.ndim != 2:
        return None
    ncols = parsed.shape[1]
    rows = []
    if ncols == 0:
        return [[i] for i in range(parsed.shape[0])]
    kk = max(0, k)
    if kk == 0:
        return [[i] for i in range(parsed.shape[0])]
    for i in range(parsed.shape[0]):
        row = parsed[i]
        # A degenerate frame (any non-finite value) yields no bins.
        if not np.all(np.isfinite(row)):
            rows.append([i])
            continue
        order = np.argsort(-row, kind="stable")
        top = order[: min(kk, ncols)]
        rows.append([i] + [int(b) for b in top])
    return rows


def main():
    if len(sys.argv) != 4:
        print("usage: peaks.py <magnitudes.npy> <k> <out.csv>", file=sys.stderr)
        sys.exit(2)
    mag_path, kstr, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
    try:
        k = int(kstr)
        rows = rows_for(mag_path, k)
        if rows is None:
            raise ValueError("not 1D/2D")
    except Exception:
        with open(out_path, "w") as fh:
            fh.write("ERROR\n")
        return
    with open(out_path, "w") as fh:
        fh.write(HEADER + "\n")
        for row in rows:
            fh.write(",".join(str(x) for x in row) + "\n")


if __name__ == "__main__":
    main()
PY

# ---------------------------------------------------------------------------
# 4. animation.py  -- emit animation records whose keyframe array lengths
#    match every timeline's declared count.
# ---------------------------------------------------------------------------
cat > /app/animation.py <<'PY'
#!/usr/bin/env python3
"""Emit animation records from a timeline spec.

Usage:  python3 /app/animation.py <spec.json> <out.json>

<spec.json> is {"timelines": [{"name": str, "keyframe_count": int}, ...]}.
The output JSON holds one record per timeline with "declared_count" and a
"keyframes" object whose time / translation / rotation / scale arrays all have
exactly that many elements (translation and scale rows have 3 components).
Counts that are missing, non-numeric, negative or fractional are emitted as
zero-length arrays.  A spec that is not valid JSON or has no "timelines" list
produces {"error": "INVALID_SPEC", "timelines": []}.
"""
import json
import random
import sys


def gen_keyframes(count, seed):
    if count <= 0:
        return {"time": [], "translation": [], "rotation": [], "scale": []}
    rng = random.Random(seed)
    step = 1.0 / count
    times = [round(i * step, 4) for i in range(count)]
    translation = [[round(rng.uniform(-10.0, 10.0), 4) for _ in range(3)]
                   for _ in range(count)]
    rotation = [round(rng.uniform(0.0, 360.0), 4) for _ in range(count)]
    scale = [[round(rng.uniform(0.2, 2.0), 4) for _ in range(3)]
             for _ in range(count)]
    return {"time": times, "translation": translation,
            "rotation": rotation, "scale": scale}


def read_spec(path):
    with open(path, "r", encoding="utf-8") as fh:
        spec = json.load(fh)
    timelines = spec["timelines"]
    if not isinstance(timelines, list):
        raise ValueError("timelines must be a list")
    return timelines


def count_of(tl):
    if not isinstance(tl, dict):
        return 0
    v = tl.get("keyframe_count", 0)
    if isinstance(v, bool) or not isinstance(v, (int, float)):
        return 0
    if isinstance(v, float) and not v.is_integer():
        return 0
    return max(0, int(v))


def main():
    if len(sys.argv) != 3:
        print("usage: animation.py <spec.json> <out.json>", file=sys.stderr)
        sys.exit(2)
    spec_path, out_path = sys.argv[1], sys.argv[2]
    try:
        timelines = read_spec(spec_path)
    except Exception:
        with open(out_path, "w", encoding="utf-8") as fh:
            json.dump({"error": "INVALID_SPEC", "timelines": []}, fh)
        return

    # "source" is part of the non-empty output; an empty timelines list
    # produces exactly {"timelines": []} per the documented contract.
    result = {"timelines": []}
    if timelines:
        result["source"] = "gryphon-anim"
    for tl in timelines:
        if isinstance(tl, dict):
            name = str(tl.get("name", "?"))
            count = count_of(tl)
        else:
            name, count = "?", 0
        result["timelines"].append({
            "name": name,
            "declared_count": count,
            "keyframes": gen_keyframes(count, seed=name),
        })
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(result, fh, indent=2)


if __name__ == "__main__":
    main()
PY

chmod +x /app/ingest.py /app/stack.py /app/peaks.py /app/animation.py

# ---------------------------------------------------------------------------
# 5. Run the tools against the shipped visible fixtures.
# ---------------------------------------------------------------------------
python3 /app/serve_media.py /app/media_src 8787 &
SERVER_PID=$!
trap 'kill $SERVER_PID 2>/dev/null || true; wait $SERVER_PID 2>/dev/null || true' EXIT
sleep 0.7

python3 /app/ingest.py \
    /app/sources.txt /app/media /app/transcript-raw.txt /app/transcript.txt

K=$(sed -n 's/^k=//p' /app/spectra_visible/settings.txt)
python3 /app/stack.py /app/tif_visible /app/stack-shape.txt /app/stack.npy
python3 /app/peaks.py /app/spectra_visible/magnitudes.npy "$K" /app/peaks.csv
python3 /app/animation.py /app/anim_visible/anim-spec.json /app/animation.json

echo "solve.sh complete"
ls -l /app/ingest.py /app/stack.py /app/peaks.py /app/animation.py /app/media/manifest.json /app/transcript-raw.txt /app/transcript.txt /app/stack-shape.txt /app/peaks.csv /app/animation.json
